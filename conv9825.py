#!/usr/bin/env python3
# Part of DUMP9825 tool
# Format converter for HP9825 tape images
#
# Copyright (c) 2022 F.Ulivi
#
# Licensed under the 3-Clause BSD License
#

import sys
import argparse
import struct
import types
import xml.etree.ElementTree as et
import re
import io
import os
import os.path

# Constants
#
# Defined record size of dump9825 format
DUMP9825_REC_SIZE = 1024
# Size of each string array element in dump & clone formats
ARRAY_EL_SIZE = 30720

# Log output if != None
log = None

# Base class of all exceptions
class MyException(Exception):
    pass

# A record
class Record:
    def __init__(self , rec_header , partitions):
        self.rec_no , self.rec_asize , self.rec_csize , self.rec_type , self.rec_rewrite , self.rec_s1 , self.rec_s2 = rec_header
        self.partitions = partitions

# A skipped record
class Skipped_record:
    def __init__(self , rec_no , msg , extracted , expected):
        self.rec_no = rec_no
        self.msg = msg
        self.extracted = extracted
        self.expected = expected

# Combine two record lists covering skipped records with good records wherever possible
def combine_records(records1 , records2):
    common_len = min(len(records1) , len(records2))
    out = []
    for r1 , r2 in zip(records1[ :common_len ] , records2[ :common_len ]):
        # r1 r2 out
        #  S  S S
        #  S  R R2
        #  R  S R1
        #  R  R R1
        if isinstance(r1 , Skipped_record):
            out.append(r2)
        else:
            out.append(r1)
    if len(records1) > common_len:
        out.extend(records1[ common_len: ])
    elif len(records2) > common_len:
        out.extend(records2[ common_len: ])
    return out

# Count total & good records
def count_records(records):
    tot = len(records)
    good = sum(map(lambda r: isinstance(r , Record) , records))
    return tot , good

# Print some statistics of a record list
def print_record_stats(records):
    tot_records  , good_records = count_records(records)
    print("Total records: {}".format(tot_records))
    print("Good records : {}".format(good_records))
    print("Missing recs : " , end="")
    if tot_records != good_records:
        first = True
        for n , r in enumerate(records):
            if isinstance(r , Skipped_record):
                if not first:
                    print(", " , end="")
                first = False
                print("{}".format(n) , end="")
        print()
    else:
        print("None")

# Compute checksum
def checksum(words):
    return sum(words) & 0xffff

# ###########
# ChunkSlicer
# ###########
class Short_chunk(MyException):
    def __init__(self):
        pass

class Bad_checksum(MyException):
    def __init__(self , words , extracted , expected):
        self.words = words
        self.extracted = extracted
        self.expected = expected

class ChunkSlicer:
    def __init__(self , obj):
        self.mv = memoryview(obj)
        self.idx = 0
        self.reserved = 0

    def available(self):
        return len(self.mv) - self.reserved - self.idx

    def get_chunk(self , size):
        if self.available() < size:
            raise Short_chunk()
        else:
            tmp = self.mv[ self.idx:self.idx+size ]
            self.idx += size
            return tmp

    def get_words(self , size):
        tmp = self.get_chunk(2 * size)
        tmpw = [ w[ 0 ] for w in struct.iter_unpack(">H" , tmp) ]
        return tmpw

    def get_checksummed_words(self , size):
        tmpw = self.get_words(size + 1)
        extracted = tmpw[ -1 ]
        words = tmpw[ :-1 ]
        expected = checksum(words)
        if extracted == expected:
            return words
        else:
            raise Bad_checksum(words , extracted , expected)

    def at_end(self):
        return self.available() <= 0

    def tell(self):
        return self.idx

    def seek_from_cur(self , delta_idx):
        self.idx += delta_idx

# Extract a single byte string from a 9845-format string array
class Collect_error(MyException):
    def __init__(self , msg):
        self.msg = msg

    def __str__(self):
        return self.msg

class Data9845:
    # End-of-record
    REC_TYPE_EOR=0x1e
    # A whole (un-split) string
    REC_TYPE_FULLSTR=0x3c
    # End-of-file
    REC_TYPE_EOF=0x3e
    # First part of a string
    REC_TYPE_1STSTR=0x1c
    # Middle part(s) of a string
    REC_TYPE_MIDSTR=0x0c
    # Last part of a string
    REC_TYPE_ENDSTR=0x2c
    # Integer
    REC_TYPE_INT=0x0a

    def __init__(self , rec_size):
        self.rec_size = rec_size
        self.data = bytearray()

    def set_data(self , data):
        self.data = data

    def get_data(self):
        return self.data

    def collect_strings(self):
        try:
            ck = ChunkSlicer(self.data)
            out = bytearray()

            while True:
                code = ck.get_words(1)[ 0 ]
                if code == self.REC_TYPE_EOR:
                    # EOR, skip to next defined record
                    pos = ck.tell() % self.rec_size
                    if pos:
                        ck.seek_from_cur(self.rec_size - pos)
                elif code == self.REC_TYPE_EOF:
                    # EOF
                    return out
                elif code == self.REC_TYPE_FULLSTR:
                    # A whole string
                    length = ck.get_words(1)[ 0 ]
                    tmp = ck.get_chunk(length)
                    out.extend(tmp)
                    if length % 2 != 0:
                        ck.seek_from_cur(1)
                elif code == self.REC_TYPE_1STSTR:
                    length = ck.get_words(1)[ 0 ]
                    pos = ck.tell() % self.rec_size
                    chunk_size = self.rec_size - pos
                    tmp = ck.get_chunk(chunk_size)
                    out.extend(tmp)
                    while True:
                        code = ck.get_words(1)[ 0 ]
                        if code == self.REC_TYPE_MIDSTR:
                            length = ck.get_words(1)[ 0 ]
                            pos = ck.tell() % self.rec_size
                            chunk_size = self.rec_size - pos
                            tmp = ck.get_chunk(chunk_size)
                            out.extend(tmp)
                        elif code == self.REC_TYPE_ENDSTR:
                            length = ck.get_words(1)[ 0 ]
                            tmp = ck.get_chunk(length)
                            out.extend(tmp)
                            break
                        else:
                            raise Collect_error("Unknown record type ({:04x}) @ {:x}".format(code , ck.tell()))
                else:
                    raise Collect_error("Unknown record type ({:04x})".format(code))
        except Short_chunk:
            raise Collect_error("Unexpected EOF")
        except Collect_error:
            raise

    def _encode_word(self , w):
        self.data.extend(struct.pack(">H" , w))

    def _idx_in_rec(self):
        return len(self.data) % self.rec_size

    def _fill_to_next_rec(self):
        while self._idx_in_rec() != 0:
            self._encode_word(self.REC_TYPE_EOR)

    def _len_to_eor(self):
        return self.rec_size - self._idx_in_rec()

    def _ensure_space(self , n):
        if self._len_to_eor() < n:
            self._fill_to_next_rec()

    def encode_integer(self , n):
        self._ensure_space(4)
        self._encode_word(self.REC_TYPE_INT)
        self._encode_word(n)

    def encode_string(self , s):
        s_len = len(s)
        idx = 0
        rec_type = self.REC_TYPE_1STSTR
        at_least_one = False
        while True:
            free_len = self._len_to_eor()
            if free_len <= 4:
                self._fill_to_next_rec()
            else:
                s_part_len = min(free_len - 4 , s_len)
                if s_part_len == s_len:
                    break
                self._encode_word(rec_type)
                self._encode_word(s_len)
                self.data.extend(s[ idx:idx+s_part_len ])
                idx += s_part_len
                s_len -= s_part_len
                rec_type = self.REC_TYPE_MIDSTR
                at_least_one = True

        self._encode_word(self.REC_TYPE_ENDSTR if at_least_one else self.REC_TYPE_FULLSTR)
        self._encode_word(s_len)
        self.data.extend(s[ idx: ])

    def pad_to_end(self):
        while self._idx_in_rec() != 0:
            self._encode_word(self.REC_TYPE_EOF)

# Conditional logging
def log_print(*args):
    if log:
        print("Log:" , *args , file = log)

def dump_words(data):
    if log:
        for idx in range(0 , len(data) , 8):
            print("{:02x} ".format(idx) , end="" , file=log)
            l = min(8 , len(data) - idx)
            for i in range(l):
                print("{:04x} ".format(data[ idx+i ]) , end="" , file=log)
            print("" , file=log)

# #####################
# dump9825 input format
# #####################
class Load_error(MyException):
    def __init__(self , msg):
        self.msg = msg

    def __str__(self):
        return self.msg

class Save_error(MyException):
    def __init__(self , msg):
        self.msg = msg

    def __str__(self):
        return self.msg

class Argument_error(MyException):
    def __init__(self , msg):
        self.msg = msg

class FormatDump9825:
    def __init__(self):
        self.track = 0
        self.records = []

    def load(self , arg):
        self.track = 0
        self.records = []
        try:
            with open(arg , "rb") as inp:
                b = inp.read()
        except OSError as e:
            raise Load_error("OS error " + e.strerror)

        data9845 = Data9845(DUMP9825_REC_SIZE)
        data9845.set_data(b)
        s = data9845.collect_strings()
        log_print("Total length of dump data: {}".format(len(s)))
        ck = ChunkSlicer(s)
        # 2 bytes are reserved at the end for error code
        ck.reserved = 2
        # State
        # 0         Wait for option word
        # 1         Wait for trace words from gap searching
        # 2         Read record header
        # 3         Read record partitions
        state = 0
        exp_rec_no = 0
        try:
            while not ck.at_end():
                if state == 0:
                    # Options
                    try:
                        tmp = ck.get_words(1)[ 0 ]
                    except Short_chunk:
                        raise Load_error("No option word")
                    if (tmp >> 8) != 250:
                        raise Load_error("Bad option word")
                    log_print("options {:02x}".format(tmp & 0x1f))
                    self.track = tmp & 1
                    state = 1
                elif state == 1:
                    try:
                        tmp = ck.get_words(1)[ 0 ]
                    except Short_chunk:
                        raise Load_error("No trace word")
                    tmp_hi = tmp >> 8
                    if tmp_hi == 120:
                        log_print("hole reached")
                    elif tmp_hi == 121:
                        log_print("gap search restarted @{}".format(tmp & 0xff))
                    elif tmp_hi == 123:
                        log_print("start normal read")
                        state = 2
                    else:
                        raise Load_error("Unexpected trace code {}".format(tmp_hi))
                elif state == 2:
                    # In normal read
                    try:
                        tmp = ck.get_words(1)[ 0 ]
                    except Short_chunk:
                        raise Load_error("No trace word")
                    if (tmp >> 8) == 30:
                        log_print("hole reached")
                        state = 1
                    else:
                        # backup if no "30" trace word
                        ck.seek_from_cur(-2)
                        try:
                            rec_hdr = ck.get_checksummed_words(7)
                            dump_words(rec_hdr)
                        except Short_chunk:
                            raise Load_error("Short rec header")
                        except Bad_checksum as e:
                            log_print("Bad checksum in rec header {:04x}/{:04x}".format(e.extracted , e.expected))
                            self.records.append(Skipped_record(exp_rec_no , "Bad checksum in rec header" , e.extracted , e.expected))
                            state = 1
                            exp_rec_no += 1
                            continue
                        if rec_hdr[ 0 ] != exp_rec_no:
                            self.records.append(Skipped_record(exp_rec_no , "Unexpected record number" , rec_hdr[ 0 ] , exp_rec_no))
                            state = 1
                            exp_rec_no += 1
                        elif rec_hdr[ 2 ] == 0:
                            # 0-sized record
                            self.records.append(Record(rec_hdr , []))
                            state = 1
                            exp_rec_no += 1
                        else:
                            state = 3
                            part_size = rec_hdr[ 2 ]
                            parts = []
                            exp_part_no = 0
                elif state == 3:
                    # In partitions
                    try:
                        part_hdr = ck.get_checksummed_words(3)
                    except Short_chunk:
                        raise Load_error("Short part header")
                    except Bad_checksum as e:
                        log_print("Bad checksum in part header {:04x}/{:04x}".format(e.extracted , e.expected))
                        self.records.append(Skipped_record(exp_rec_no , "Bad checksum in part header" , e.extracted , e.expected))
                        state = 1
                        exp_rec_no += 1
                        continue
                    if part_hdr[ 0 ] != exp_part_no:
                        self.records.append(Skipped_record(exp_rec_no , "Unexpected partition number" , part_hdr[ 0 ] , exp_part_no))
                        state = 1
                        exp_rec_no += 1
                    elif part_hdr[ 2 ] != rec_hdr[ 4 ]:
                        self.records.append(Skipped_record(exp_rec_no , "Bad rewrite number" , part_hdr[ 2 ] , rec_hdr[ 4 ]))
                        state = 1
                        exp_rec_no += 1
                    elif part_hdr[ 1 ] == 0 or part_hdr[ 1 ] > part_size:
                        self.records.append(Skipped_record(exp_rec_no , "Bad partition size" , part_hdr[ 1 ] , part_size))
                        state = 1
                        exp_rec_no += 1
                    else:
                        try:
                            part_data = ck.get_checksummed_words(part_hdr[ 1 ])
                        except Short_chunk:
                            raise Load_error("Short part data")
                        except Bad_checksum as e:
                            log_print("Bad checksum in part data {:04x}/{:04x}".format(e.extracted , e.expected))
                            self.records.append(Skipped_record(exp_rec_no , "Bad checksum in part data" , e.extracted , e.expected))
                            state = 1
                            exp_rec_no += 1
                            continue
                        parts.append((part_hdr[ 0 ] , part_hdr[ 1 ] , part_hdr[ 2 ] , part_data))
                        part_size -= part_hdr[ 1 ]
                        if part_size == 0:
                            self.records.append(Record(rec_hdr , parts))
                            state = 1
                            exp_rec_no += 1
                        else:
                            exp_part_no += 1
        finally:
            ck.reserved = 0
            ck.idx = len(ck.mv) - 2
            try:
                tmp = ck.get_words(1)[ 0 ]
                if (tmp >> 8) == 251:
                    log_print("E = {}".format(tmp & 0xff))
            except Short_chunk:
                raise Load_error("No E value")

    def get_track_records(self , arg_track):
        return self.track , self.records

    def get_av_tracks(self):
        return 1

# #######################
# HTI input/output format
# #######################
class Bit_serializer:
    def __init__(self , words):
        self.words = words
        self.g = self.get_bit()
        self.mask = 0

    def get_bit(self):
        for w in self.words:
            mask = 0x8000
            while mask != 0:
                yield (w & mask) != 0
                mask >>= 1

    def get_synchronized_bits(self):
        bit = False
        while not bit:
            bit = next(self.g)
        while True:
            yield next(self.g)

    def get_17bit_words(self):
        self.mask = 0x10000
        w = 0
        for bit in self.get_synchronized_bits():
            if self.mask == 0x10000:
                if not bit:
                    # TODO:
                    pass
            else:
                if bit:
                    w |= self.mask
            self.mask >>= 1
            if self.mask == 0:
                self.mask = 0x10000
                yield w
                w = 0

    def resync(self):
        if self.mask == 0x10000:
            # Avoid resynchronizing on 17th bit
            bit = next(self.g)

class No_more_bits(MyException):
    pass

ZERO_BIT_LEN=619
ONE_BIT_LEN=1083
ONE_INCH_POS=968*1024
START_POS=int(72.2 * ONE_INCH_POS)
MAX_POS=1752 * ONE_INCH_POS

def word_length(w):
    ones = (w & 0x5555) + ((w >> 1) & 0x5555)
    ones = (ones & 0x3333) + ((ones >> 2) & 0x3333)
    ones = (ones & 0x0f0f) + ((ones >> 4) & 0x0f0f)
    ones = (ones & 0x00ff) + ((ones >> 8) & 0x00ff)
    zeros = 16 - ones;
    return zeros * ZERO_BIT_LEN + ones * ONE_BIT_LEN

class TapeFormatWords:
    def __init__(self , start):
        self.start = start
        self.words = []

    def append(self , w):
        self.words.append(w)

class TapeFormatGap:
    def __init__(self , length):
        self.length = length

class TapeFormatter:
    DZ_WORDS=403
    EVD_SIZE=6 * ONE_INCH_POS
    SKIPPED_REC_ASIZE=128
    PREAMBLE=1
    IRG_SIZE=ONE_INCH_POS
    IPG_SIZE=12000

    def __init__(self):
        self.encoded = []

    def _close_current(self):
        if self.current is not None:
            self.current.end = self.encode_pos
            self.encoded.append(self.current)
        self.current = None

    def _encode_word(self , w):
        if not isinstance(self.current , TapeFormatWords):
            self._close_current()
            self.current = TapeFormatWords(self.encode_pos)
        self.current.append(w)
        self.encode_pos += word_length(w)
        self.encode_pos += ONE_BIT_LEN
        if self.encode_pos > (MAX_POS - self.EVD_SIZE):
            raise Save_error("Out of space")

    def _encode_data(self , data):
        for w in data:
            self._encode_word(w)

    def _encode_ones(self , n):
        self._encode_data([ 0xffff ] * n)

    def _encode_deadzone(self):
        self._encode_ones(self.DZ_WORDS)

    def _encode_preamble_data_csum(self , data , csum_xor = 0):
        csum = checksum(data)
        self._encode_word(self.PREAMBLE)
        self._encode_data(data)
        self._encode_word(csum ^ csum_xor)

    def _compute_mark_size(self , asize):
        # See 9825T firmware @ 20751o
        n_recs = asize // 128
        if asize % 128 != 0:
            n_recs += 1
        n_words = asize + n_recs * 10
        n_words += n_words // 8
        n_words += 7
        return n_words

    def _encode_gap(self , size):
        self._close_current()
        self.encoded.append(TapeFormatGap(size))
        self.encode_pos += size

    def _encode_irg(self):
        self._encode_gap(self.IRG_SIZE)

    def _encode_ipg(self):
        self._encode_gap(self.IPG_SIZE)

    def encode_track(self , records , extra_postamble = False):
        self.encode_pos = START_POS
        self.encoded = []
        self.current = None
        self._encode_deadzone()
        for r in records:
            if isinstance(r , Record):
                # Standard record
                rec_hdr = [ r.rec_no , r.rec_asize , r.rec_csize , r.rec_type , r.rec_rewrite , r.rec_s1 , r.rec_s2 ]
                parts = r.partitions
            else:
                # Skipped record
                rec_hdr = [ r.rec_no , self.SKIPPED_REC_ASIZE , 0 , 0 , 0 , 0 , 0 ]
                parts = []
            # Compute record size when marked
            # Record header during marking:
            # 0    Record #
            # 1    Absolute size
            # 2..6 = 0000
            # 7    Checksum
            hdr_size = word_length(self.PREAMBLE) + \
                word_length(rec_hdr[ 0 ]) + \
                word_length(rec_hdr[ 1 ]) + \
                5 * word_length(0) + \
                word_length(checksum(rec_hdr[ 0:2 ])) + \
                9 * ONE_BIT_LEN
            # count of ffff words when marking
            mark_words = self._compute_mark_size(rec_hdr[ 1 ])
            mark_size = 17 * ONE_BIT_LEN * mark_words + hdr_size
            log_print("Mark size of rec {}, asize {} = {}".format(rec_hdr[ 0 ] , rec_hdr[ 1 ] , mark_size))
            # Encode rec header
            self._encode_irg()
            # This is the ending position of record when marked
            mark_end_pos = self.encode_pos + mark_size
            if isinstance(r , Record):
                self._encode_preamble_data_csum(rec_hdr)
            else:
                # Skipped records are intentionally stored with wrong checksum (to mark them as such)
                self._encode_preamble_data_csum(rec_hdr , 0xffff)
            self._encode_word(self.PREAMBLE)
            if extra_postamble:
                self._encode_word(self.PREAMBLE)
            # Encode partitions
            for part_no , part_size , part_rewrite , part_data in parts:
                self._encode_ipg()
                self._encode_preamble_data_csum([ part_no , part_size , part_rewrite ])
                self._encode_preamble_data_csum(part_data)
                self._encode_word(self.PREAMBLE)
                if extra_postamble:
                    self._encode_word(self.PREAMBLE)
            # Now, fill with FFFF words up to the end of marked size
            if self.encode_pos < mark_end_pos:
                filler = (mark_end_pos - self.encode_pos) // (17 * ONE_BIT_LEN)
                self._encode_ones(filler)
            else:
                log_print("Record {} is bigger than its marked size ({})???".format(rec_hdr[ 0 ] , rec_hdr[ 1 ]))
        self._encode_gap(self.EVD_SIZE)
        return self.encoded

class FormatHTI:
    MAGIC=b"HTI0"
    MIN_IRG_SIZE=int(0.5 * ONE_INCH_POS)
    MIN_IPG_SIZE=1

    def __init__(self):
        self.track_images = None
        self.track = None

    def _load(self , infile):
        try:
            with open(infile , "rb") as inp:
                magic = inp.read(4)
                if magic != self.MAGIC:
                    raise Load_error("Bad magic word")
                t0 = self._load_track_image(inp)
                t1 = self._load_track_image(inp)
                self.track_images = [ t0 , t1 ]
        except struct.error:
            raise Load_error("Short image file")

    def load(self , arg):
        try:
            self._load(arg)
        except OSError as e:
            raise Load_error("OS error " + e.strerror)

    def _load_track_image(self , inp):
        image = []
        while True:
            tmp = inp.read(4)
            n_words = struct.unpack("<i" , tmp)[ 0 ]
            if n_words < 0:
                break
            tmp = inp.read(4)
            pos = struct.unpack("<L" , tmp)[ 0 ]
            size = 0
            words = []
            for i in range(n_words):
                w = struct.unpack("<H" , inp.read(2))[ 0 ]
                words.append(w)
                size += word_length(w)
            image.append((pos , pos + size , words))
        return image

    def get_track_records(self , arg_track):
        records = self._decode_track(self.track_images[ arg_track ])
        return arg_track , records

    def get_av_tracks(self):
        return 2

    def get_max_tracks(self):
        return 2

    def _skip_to_next_block(self , image , pos , min_gap):
        skipping = True
        for blk_pos , blk_end_pos , words in image:
            if skipping:
                if pos <= blk_end_pos:
                    skipping = False
                    last_blk_end = blk_end_pos
            elif (blk_pos - last_blk_end) >= min_gap:
                return blk_pos , blk_end_pos , words
            else:
                last_blk_end = blk_end_pos
        return 0 , 0 , None

    def _get_words(self , size , bit_gen):
        try:
            g = bit_gen.get_17bit_words()
            words = [ next(g) for i in range(size) ]
            return words
        except StopIteration:
            raise No_more_bits()

    def _get_checksummed_words(self , size , bit_gen):
        tmpw = self._get_words(size + 1 , bit_gen)
        extracted = tmpw[ -1 ]
        words = tmpw[ :-1 ]
        expected = checksum(words)
        if extracted == expected:
            return words
        else:
            raise Bad_checksum(words , extracted , expected)

    def _decode_record(self , image , pos , exp_rec_no):
        new_pos , end_pos , words = self._skip_to_next_block(image , pos , self.MIN_IRG_SIZE)
        if not words:
            return end_pos , None
        log_print("{}->{}-{}".format(pos , new_pos , end_pos))
        pos = end_pos
        g = Bit_serializer(words)
        try:
            rec_hdr = self._get_checksummed_words(7 , g)
            log_print("Rec HDR")
            dump_words(rec_hdr)
        except No_more_bits:
            raise Load_Error("Short rec header")
        except Bad_checksum as e:
            log_print("Bad checksum in rec header {:04x}/{:04x}".format(e.extracted , e.expected))
            return pos , Skipped_record(exp_rec_no , "Bad checksum in rec header" , e.extracted , e.expected)
        if rec_hdr[ 0 ] != exp_rec_no:
            return pos , Skipped_record(exp_rec_no , "Unexpected record number" , rec_hdr[ 0 ] , exp_rec_no)
        else:
            part_size = rec_hdr[ 2 ]
            parts = []
            exp_part_no = 0
            while part_size > 0:
                new_pos , end_pos , words = self._skip_to_next_block(image , pos , self.MIN_IPG_SIZE)
                if not words:
                    break
                log_print("{}->{}-{}".format(pos , new_pos , end_pos))
                pos = end_pos
                g = Bit_serializer(words)
                try:
                    part_hdr = self._get_checksummed_words(3 , g)
                    log_print("Part HDR")
                    dump_words(part_hdr)
                except No_more_bits:
                    raise Load_Error("Short part header")
                except Bad_checksum as e:
                    log_print("Bad checksum in part header {:04x}/{:04x}".format(e.extracted , e.expected))
                    return pos , Skipped_record(exp_rec_no , "Bad checksum in part header" , e.extracted , e.expected)
                if part_hdr[ 0 ] != exp_part_no:
                    return pos , Skipped_record(exp_rec_no , "Unexpected partition number" , part_hdr[ 0 ] , exp_part_no)
                elif part_hdr[ 2 ] != rec_hdr[ 4 ]:
                    return pos , Skipped_record(exp_rec_no , "Bad rewrite number" , part_hdr[ 2 ] , rec_hdr[ 4 ])
                elif part_hdr[ 1 ] == 0 or part_hdr[ 1 ] > part_size:
                    return pos , Skipped_record(exp_rec_no , "Bad partition size" , part_hdr[ 1 ] , part_size)
                else:
                    try:
                        g.resync()
                        part_data = self._get_checksummed_words(part_hdr[ 1 ] , g)
                    except No_more_bits:
                        raise Load_error("Short part data")
                    except Bad_checksum as e:
                        log_print("Bad checksum in part data {:04x}/{:04x}".format(e.extracted , e.expected))
                        return pos , Skipped_record(exp_rec_no , "Bad checksum in part data" , e.extracted , e.expected)
                    parts.append((part_hdr[ 0 ] , part_hdr[ 1 ] , part_hdr[ 2 ] , part_data))
                    part_size -= part_hdr[ 1 ]
                    exp_part_no += 1
            if part_size > 0:
                # Premature end of data
                log_print("Premature end of partitions")
                return pos , Skipped_record(exp_part_no , "Premature end of partitions" , 0 , part_size)
            else:
                return pos , Record(rec_hdr , parts)

    def _decode_track(self , image):
        pos = START_POS
        records = []
        exp_rec_no = 0
        while True:
            pos , record = self._decode_record(image , pos , exp_rec_no)
            if not record:
                break
            if isinstance(record , Record):
                log_print("Good record {}, len={}".format(record.rec_no , record.rec_csize))
            else:
                log_print("Skipped record {}, {} {:04x}/{:04x}".format(record.rec_no , record.msg , record.extracted , record.expected))
            records.append(record)
            exp_rec_no += 1
        return records

    def _start_word(self):
        self.mask = 0x8000
        self.temp_w = 0

    def _start_block(self):
        self._start_word()
        self.block_data = []

    def _store_word(self):
        self.block_data.append(self.temp_w)

    def _store_block(self , encode_pos , size):
        if self.mask != 0x8000:
            self._store_word()
            # Take into account extra zeroes and advance end position
            while self.mask != 0:
                self.mask >>= 1
                size += ZERO_BIT_LEN
        if self.block_data:
            self.track_images[ self.track ].append((encode_pos , encode_pos + size , self.block_data))
        return encode_pos + size

    def _encode_bit(self , bit):
        if bit:
            self.temp_w |= self.mask
        self.mask >>= 1
        if self.mask == 0:
            self._store_word()
            self._start_word()

    def _encode_17bit_word(self , w):
        m = 0x8000
        while m != 0:
            self._encode_bit(w & m)
            m >>= 1
        self._encode_bit(1)

    def _encode_data(self , data):
        for w in data:
            self._encode_17bit_word(w)

    def _encode_track(self , track , records):
        self.track = track
        self.track_images[ self.track ] = []
        if records:
            formatter = TapeFormatter()
            encoded = formatter.encode_track(records)
            encode_pos = START_POS
            for f in encoded:
                if isinstance(f , TapeFormatWords):
                    self._start_block()
                    self._encode_data(f.words)
                    encode_pos = self._store_block(encode_pos , f.end - f.start)
                else:
                    encode_pos += f.length

    def set_track_records(self , arg , track , records):
        if self.track_images is None:
            try:
                self._load(arg)
            except OSError:
                self.track_images = [ [] , [] ]
        dec_records = self._decode_track(self.track_images[ track ])
        dec_records = combine_records(dec_records , records)
        self._encode_track(track , dec_records)
        return dec_records

    def save(self , arg):
        try:
            with open(arg , "wb") as out:
                out.write(self.MAGIC)
                self._save_track_image(out , self.track_images[ 0 ])
                self._save_track_image(out , self.track_images[ 1 ])
        except OSError as e:
            raise Save_error("OS error " + e.strerror)

    def _save_track_image(self , out , image):
        for pos , _ , words in image:
            out.write(struct.pack("<i" , len(words)))
            out.write(struct.pack("<L" , pos))
            for w in words:
                out.write(struct.pack("<H" , w))
        out.write(struct.pack("<i" , -1))

# ###################
# Clone output format
# ###################
class FormatClone:
    OP_TERMINATE=0
    OP_WR_WORDS=1
    OP_WR_GAP=2
    OP_WR_REPEAT=3
    MIN_REPEAT=4

    def __init__(self):
        self.track_image = bytearray()

    def get_max_tracks(self):
        return 1

    def _encode_word(self , w):
        self.track_image.extend(struct.pack(">H" , w))

    def _encode_cmd(self , op , cnt):
        w = (op << 14) | cnt
        self._encode_word(w)

    def _encode_wr_words(self , words):
        self._encode_cmd(self.OP_WR_WORDS , len(words))
        for w in words:
            self._encode_word(w)

    def _encode_wr_repeat(self , cnt , word):
        self._encode_cmd(self.OP_WR_REPEAT , cnt)
        self._encode_word(word)

    def set_track_records(self , arg , track , records):
        self.track = track
        self.track_image = bytearray()
        if records:
            formatter = TapeFormatter()
            encoded = formatter.encode_track(records , True)
            for f in encoded:
                if isinstance(f , TapeFormatWords):
                    accum = []
                    rep_word = 0
                    rep_cnt = 0
                    # First word is preamble and it's always skipped
                    for w in f.words[ 1: ]:
                        if rep_cnt == 0:
                            rep_word = w
                            rep_cnt = 1
                        elif rep_word == w:
                            rep_cnt += 1
                        else:
                            if rep_cnt < self.MIN_REPEAT:
                                accum.extend([ rep_word ] * rep_cnt)
                            else:
                                if accum:
                                    self._encode_wr_words(accum)
                                    accum = []
                                self._encode_wr_repeat(rep_cnt , rep_word)
                            rep_word = w
                            rep_cnt = 1
                    if rep_cnt < self.MIN_REPEAT:
                        accum.extend([ rep_word ] * rep_cnt)
                        rep_cnt = 0
                    if accum:
                        self._encode_wr_words(accum)
                    if rep_cnt > 0:
                        self._encode_wr_repeat(rep_cnt , rep_word)
                else:
                    # Encode a gap
                    self._encode_cmd(self.OP_WR_GAP , (f.length + 1023) // 1024)
            # Encode termination
            self._encode_cmd(self.OP_TERMINATE , 0)
        return records

    def save(self , arg):
        # l = len(self.track_image)
        # for i in range(0 , l , 32):
        #     print("{:04x} ".format(i // 2) , end="")
        #     for j in range(0 , min(32 , l - i) , 2):
        #         print(" {:02x}{:02x}".format(self.track_image[ i + j ] , self.track_image[ i + j + 1 ]) , end="")
        #     print("")

        data = Data9845(DUMP9825_REC_SIZE)
        n_strings = (len(self.track_image) + ARRAY_EL_SIZE - 1) // ARRAY_EL_SIZE
        data.encode_integer(self.track)
        data.encode_integer(n_strings)
        for idx in range(0 , len(self.track_image) , ARRAY_EL_SIZE):
            l = min(ARRAY_EL_SIZE , len(self.track_image) - idx)
            data.encode_string(self.track_image[ idx:idx+l ])
        data.pad_to_end()
        with open(arg , "wb") as out:
            out.write(data.get_data())

# #######################
# directory output format
# #######################
class FormatDirectory:
    def __init__(self):
        self.track = 0
        self.records = []

    def get_max_tracks(self):
        return 1

    def set_track_records(self , arg , track , records):
        self.track = track
        self.records = records
        return records

    def save(self , arg):
        if os.path.exists(arg):
            if not os.path.isdir(arg):
                raise Save_error("{} must be a directory".format(arg))
        else:
            try:
                os.mkdir(arg)
            except OSError as e:
                raise Save_error("OS error " + e.strerror)
        with open(os.path.join(arg , "manifest.txt") , "wt" , encoding = "ascii") as out:
            print("**** Track {} ****".format(self.track) , file=out)
            for rec_no , r in enumerate(self.records):
                print("**** Record {} ****".format(rec_no) , file=out)
                if isinstance(r , Record):
                    print("Abs size : {}".format(r.rec_asize) , file=out)
                    print("Curr size: {}".format(r.rec_csize) , file=out)
                    print("Type     : {}".format(r.rec_type) , file=out)
                    print("Rewrite #: {}".format(r.rec_rewrite) , file=out)
                    print("S1       : {:04x}".format(r.rec_s1) , file=out)
                    print("S2       : {:04x}".format(r.rec_s2) , file=out)
                    print("" , file=out)
                    parts = r.partitions
                    if parts:
                        with open(os.path.join(arg , "rec{:03}.bin".format(rec_no)) , "wb") as rec_file:
                            for part_no , part_size , part_rewrite , part_data in parts:
                                print("Part no  : {}".format(part_no) , file=out)
                                print("Part size: {}".format(part_size) , file=out)
                                print("Part rewr: {}".format(part_rewrite) , file=out)
                                for w in part_data:
                                    rec_file.write(struct.pack(">H" , w))
                else:
                    print("SKIPPED" , file=out)
                print("" , file=out)

# #######################
# XML input/output format
# #######################
class FormatXML:
    def __init__(self):
        self.track_images = None

    def _get_int_attr(self , el , attr , base = 10):
        attrv = el.get(attr)
        if attrv is None:
            raise Load_error("Missing {} attribute".format(attr))
        try:
            attrn = int(attrv , base)
            if attrn < 0 or attrn > 65535:
                raise Load_error("Invalid value ({}) for attribute {}".format(attrn , attr))
        except ValueError:
            raise Load_error("Bad {} attribute".format(attr))
        return attrn

    def _decode_record(self , el):
        rec_no = self._get_int_attr(el , "rec_no")
        rec_asize = self._get_int_attr(el , "rec_asize")
        rec_csize = self._get_int_attr(el , "rec_csize")
        rec_type = self._get_int_attr(el , "rec_type")
        rec_rewrite = self._get_int_attr(el , "rec_rewrite")
        rec_s1 = self._get_int_attr(el , "rec_s1" , 16)
        rec_s2 = self._get_int_attr(el , "rec_s2" , 16)
        # Sanity check..
        if rec_asize < rec_csize:
            raise Load_error("Invalid asize/csize = {},{}".format(rec_asize , rec_csize))
        parts = []
        exp_part_no = 0
        size = rec_csize
        for subel in el:
            if subel.tag != "Partition":
                raise Load_error("Unknown tag ({}) where Partition is expected".format(subel.tag))
            part_no = self._get_int_attr(subel , "part_no")
            part_size = self._get_int_attr(subel , "part_size")
            part_rewrite = self._get_int_attr(subel , "part_rewrite")
            if part_no != exp_part_no:
                raise Load_error("Wrong partition sequence")
            if part_size == 0:
                raise Load_error("Partition with null size")
            if part_size > size:
                raise Load_error("Invalid partition size ({}>{})".format(part_size , size))
            if part_rewrite != rec_rewrite:
                raise Load_error("Bad rewrite number")
            txt = subel.text
            if not txt:
                raise Load_error("Empty partition")
            split_text = re.split(r"([0-9a-fA-F]{4})" , txt)
            words = []
            for idx in range(0 , len(split_text) - 1 , 2):
                if not split_text[ idx ].isspace():
                    raise Load_error("Garbage in partition data")
                words.append(int(split_text[ idx + 1 ] , 16))
            if split_text[ -1 ] != "" and not split_text[ -1 ].isspace():
                raise Load_error("Garbage in partition data")
            if len(words) != part_size:
                raise Load_error("Wrong size of partition data ({},{})".format(len(words) , part_size))
            size -= part_size
            exp_part_no += 1
            parts.append((part_no , part_size , part_rewrite , words))
        if size != 0:
            raise Load_error("Missing partitions")
        return Record((rec_no , rec_asize , rec_csize , rec_type , rec_rewrite , rec_s1 , rec_s2) , parts)

    def _decode_skippedrecord(self , el):
        rec_no = self._get_int_attr(el , "rec_no")
        return Skipped_record(rec_no , "" , 0 , 0)

    def _load(self , arg):
        try:
            self.track_images = [ [] , [] ]
            xml_doc = et.parse(arg)
            xml_root = xml_doc.getroot()
            if xml_root is None or xml_root.tag != "Dump9825":
                raise Load_error("Bad root node")
            for el in xml_root.iterfind("Track"):
                track_attr = el.get("track")
                if track_attr is None:
                    raise Load_error("Missing track attribute")
                try:
                    track_no = int(track_attr)
                except ValueError:
                    raise Load_error("Bad track attribute")
                if track_no != 0 and track_no != 1:
                    raise Load_error("Invalid track number")
                if self.track_images[ track_no ]:
                    raise Load_error("Track {} doubly defined".format(track_no))
                recs = []
                exp_rec_no = 0
                for subel in el:
                    if subel.tag == "Record":
                        rec = self._decode_record(subel)
                        if rec.rec_no != exp_rec_no:
                            raise Load_error("Wrong record sequence")
                        recs.append(rec)
                        exp_rec_no += 1
                    elif subel.tag == "SkippedRecord":
                        rec = self._decode_skippedrecord(subel)
                        if rec.rec_no != exp_rec_no:
                            raise Load_error("Wrong record sequence")
                        recs.append(rec)
                        exp_rec_no += 1
                    else:
                        log_print("Unknown tag {} ignored..".format(subel.tag))
                self.track_images[ track_no ] = recs
        except et.ParseError as e:
            raise Load_error("XML parsing error: " + str(e))

    def load(self , arg):
        try:
            self._load(arg)
        except OSError as e:
            raise Load_error("OS error " + e.strerror)

    def get_track_records(self , arg_track):
        recs = self.track_images[ arg_track ]
        return arg_track , recs

    def get_av_tracks(self):
        return 2

    def get_max_tracks(self):
        return 2

    def set_track_records(self , arg , track , records):
        if self.track_images is None:
            try:
                self._load(arg)
            except OSError:
                self.track_images = [ [] , [] ]
        records = combine_records(self.track_images[ track ] , records)
        self.track_images[ track ] = records
        return records

    def save(self , arg):
        try:
            top = et.Element("Dump9825")
            for track_no , track in enumerate(self.track_images):
                if track:
                    track_el = et.Element("Track")
                    track_el.set("track" , str(track_no))
                    top.append(track_el)
                    for rec_no , r in enumerate(track):
                        if isinstance(r , Record):
                            rec_el = et.Element("Record")
                            rec_el.set("rec_asize" , str(r.rec_asize))
                            rec_el.set("rec_csize" , str(r.rec_csize))
                            rec_el.set("rec_type" , str(r.rec_type))
                            rec_el.set("rec_rewrite" , str(r.rec_rewrite))
                            rec_el.set("rec_s1" , "{:04x}".format(r.rec_s1))
                            rec_el.set("rec_s2" , "{:04x}".format(r.rec_s2))
                            for part_no , part in enumerate(r.partitions):
                                part_el = et.Element("Partition")
                                part_el.set("part_no" , str(part_no))
                                part_el.set("part_size" , str(part[ 1 ]))
                                part_el.set("part_rewrite" , str(part[ 2 ]))
                                txts = io.StringIO()
                                for nw , w in enumerate(part[ 3 ]):
                                    if nw % 8 == 0:
                                        print("\n        " , end="" , file=txts)
                                    print("{:04x} ".format(w) , end="" , file=txts)
                                print("" , file=txts)
                                part_el.text = txts.getvalue()
                                rec_el.append(part_el)
                        else:
                            rec_el = et.Element("SkippedRecord")
                        rec_el.set("rec_no" , str(rec_no))
                        track_el.append(rec_el)
            root = et.ElementTree(top)
            root.write(arg , xml_declaration = True)
        except OSError as e:
            raise Save_error("OS error " + e.strerror)

# Formats
FORMATS = {
    "dump" : FormatDump9825,
    "hti"  : FormatHTI,
    "dir"  : FormatDirectory,
    "xml"  : FormatXML,
    "clone": FormatClone
}

def main():
    # Compile input/output format lists
    in_formats = []
    out_formats = []
    for name , cls in FORMATS.items():
        if isinstance(cls.__dict__.get("load" , None) , types.FunctionType):
            in_formats.append(name)
        if isinstance(cls.__dict__.get("save" , None) , types.FunctionType):
            out_formats.append(name)

    parser = argparse.ArgumentParser(description='Convert 9825 tape formats')
    parser.add_argument("--track" , type=int , choices=[ 0 , 1 ] , help = "Set track, either 0 or 1")
    parser.add_argument("in_arg" , help = "Input file or directory")
    parser.add_argument("in_fmt" , choices=in_formats , help = "Input format")
    parser.add_argument("out_arg" , help = "Output file or directory")
    parser.add_argument("out_fmt" , choices=out_formats , help = "Output format")
    args = parser.parse_args()

    global log
    log = sys.stderr

    try:
        if args.out_fmt == args.in_fmt:
            raise Argument_error("Same format for input & output")

        inp = FORMATS[ args.in_fmt ]()
        out = FORMATS[ args.out_fmt ]()

        # IN av OUT max --track switch
        # 1     1       must not be specified
        # 1     2       must not be specified
        # 2     1       must be specified
        # 2     2       may be specified
        if inp.get_av_tracks() == 1 and args.track is not None:
            raise Argument_error("--track must not be specified")
        elif inp.get_av_tracks() == 2 and out.get_max_tracks() == 1 and args.track is None:
            raise Argument_error("--track must be specified")

        print("Loading with {} format...".format(args.in_fmt))
        inp.load(args.in_arg)

        for track_idx in range(2):
            if track_idx == 1 and inp.get_av_tracks() == 1:
                break
            if args.track is not None and track_idx != args.track:
                continue
            track , records = inp.get_track_records(track_idx)
            print_record_stats(records)

            saved_records = out.set_track_records(args.out_arg , track , records)
            print_record_stats(saved_records)
        print("\nSaving with {} format...".format(args.out_fmt))
        out.save(args.out_arg)
        print("Done!")
    except Load_error as e:
        print("Loading error:" + e.msg , file = sys.stderr)
    except Save_error as e:
        print("Saving error:" + e.msg , file = sys.stderr)
    except Argument_error as e:
        print("Argument error:" + e.msg , file = sys.stderr)
    except Collect_error as e:
        print("String collection error:" + e.msg , file = sys.stderr)

if __name__ == '__main__':
    main()

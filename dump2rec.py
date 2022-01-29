#!/usr/bin/env python3
# Part of DUMP9825 tool
#
# Copyright (c) 2021 F.Ulivi
#
# Licensed under the 3-Clause BSD License
#

import sys
import argparse
import struct
import os
import os.path
import stat

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

DEBUG=False

class Collect_error(Exception):
    def __init__(self , msg):
        self.msg = msg

    def __str__(self):
        return self.msg

def collect_strings(inp , def_record_size):
    try:
        out = bytearray()
        while True:
            tmp = inp.read(2)
            code = struct.unpack(">H" , tmp)[ 0 ]
            if code == REC_TYPE_EOR:
                # EOR, skip to next defined record
                pos = inp.tell() % def_record_size
                if pos:
                    pos = def_record_size - pos
                inp.seek(pos , SEEK_CUR)
            elif code == REC_TYPE_EOF:
                # EOF
                return out
            elif code == REC_TYPE_FULLSTR:
                # A whole string
                tmp = inp.read(2)
                length = struct.unpack(">H" , tmp)[ 0 ]
                tmp = inp.read(length)
                out.extend(tmp)
                if length % 2 != 0:
                    tmp = inp.read(1)
            elif code == REC_TYPE_1STSTR:
                tmp = inp.read(2)
                length = struct.unpack(">H" , tmp)[ 0 ]
                pos = inp.tell() % def_record_size
                chunk_size = def_record_size - pos
                tmp = inp.read(chunk_size)
                out.extend(tmp)
                while True:
                    tmp = inp.read(2)
                    code = struct.unpack(">H" , tmp)[ 0 ]
                    if code == REC_TYPE_MIDSTR:
                        tmp = inp.read(2)
                        length = struct.unpack(">H" , tmp)[ 0 ]
                        pos = inp.tell() % def_record_size
                        chunk_size = def_record_size - pos
                        tmp = inp.read(chunk_size)
                        out.extend(tmp)
                    elif code == REC_TYPE_ENDSTR:
                        tmp = inp.read(2)
                        length = struct.unpack(">H" , tmp)[ 0 ]
                        tmp = inp.read(length)
                        out.extend(tmp)
                        break
                    else:
                        raise Collect_error("Unknown record type ({:04x}) @ {:x}".format(code , inp.tell()))
            else:
                raise Collect_error("Unknown record type ({:04x})".format(code))
    except struct.error:
        raise Collect_error("Unexpected EOF")
    except OSError as e:
        raise Collect_error("OSError:" + e.strerror)

class Record_error(Exception):
    def __init__(self , msg):
        self.msg = msg

    def __str__(self):
        return self.msg

def dump(data , out):
    for idx in range(0 , len(data) , 16):
        print("{:02x} ".format(idx // 2) , end="" , file=out)
        l = min(16 , len(data) - idx)
        for i in range(0 , l , 2):
            print("{:02x}{:02x} ".format(data[ idx+i ] , data[ idx+i+1 ]) , end="" , file=out)
        print("" , file=out)

def dump_words(data , out):
    for idx in range(0 , len(data) , 8):
        print("{:02x} ".format(idx) , end="" , file=out)
        l = min(8 , len(data) - idx)
        for i in range(l):
            print("{:04x} ".format(data[ idx+i ]) , end="" , file=out)
        print("" , file=out)

class Short_chunk(Exception):
    def __init__(self):
        pass

class Bad_checksum(Exception):
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
        expected = sum(words) & 0xffff
        if extracted == expected:
            return words
        else:
            raise Bad_checksum(words , extracted , expected)

    def at_end(self):
        return self.available() <= 0

class Skipped_record:
    def __init__(self , rec_no , msg , extracted , expected):
        self.rec_no = rec_no
        self.msg = msg
        self.extracted = extracted
        self.expected = expected

def get_records(s):
    ck = ChunkSlicer(s)
    log_state = 0
    exp_rec_no = 0
    try:
        while not ck.at_end():
            # Check for trace logs
            try:
                tmp = ck.get_words(1)[ 0 ]
            except Short_chunk:
                raise Record_error("No trace word")
            tmp_hi = tmp >> 8
            if log_state == 0:
                if tmp_hi == 250:
                    print("Log: options {:02x}".format(tmp & 0x1f))
                    ck.reserved = 2
                elif tmp_hi == 120:
                    print("Log: hole reached")
                elif tmp_hi == 121:
                    print("Log: gap search restarted @{}".format(tmp & 0xff))
                elif tmp_hi == 123:
                    print("Log: start normal read")
                    log_state = 2
                else:
                    raise Record_error("Unexpected trace code {}".format(tmp_hi))
            elif log_state == 2:
                # In normal read
                if tmp_hi == 30:
                    print("Log: hole reached (normal mode)")
                    log_state = 0
                else:
                    ck.idx -= 2
                    try:
                        rec_hdr = ck.get_checksummed_words(7)
                    except Short_chunk:
                        raise Record_error("Short rec header")
                    except Bad_checksum as e:
                        if DEBUG:
                            dump_words(e.words , sys.stderr)
                            print("Bad checksum in rec header {:04x}/{:04x}".format(e.extracted , e.expected) , file = sys.stderr)
                        yield Skipped_record(exp_rec_no , "Bad checksum in rec header" , e.extracted , e.expected)
                        log_state = 0
                        exp_rec_no += 1
                        continue
                    if DEBUG:
                        print("Rec Header: {}".format(rec_hdr) , file = sys.stderr)
                    if rec_hdr[ 0 ] != exp_rec_no:
                        yield Skipped_record(exp_rec_no , "Unexpected record number" , rec_hdr[ 0 ] , exp_rec_no)
                        log_state = 0
                        exp_rec_no += 1
                    elif rec_hdr[ 2 ] == 0:
                        # 0-sized record
                        yield (rec_hdr[ 0 ] , rec_hdr[ 1 ] , rec_hdr[ 2 ] , rec_hdr[ 3 ] , rec_hdr[ 4 ] , rec_hdr[ 5 ] , rec_hdr[ 6 ] , [])
                        log_state = 0
                        exp_rec_no += 1
                    else:
                        log_state = 3
                        part_size = rec_hdr[ 2 ]
                        parts = []
                        exp_part_no = 0
            elif log_state == 3:
                # In partitions
                ck.idx -= 2
                try:
                    part_hdr = ck.get_checksummed_words(3)
                except Short_chunk:
                    raise Record_error("Short part header")
                except Bad_checksum as e:
                    if DEBUG:
                        dump_words(e.words , sys.stderr)
                        print("Bad checksum in part header {:04x}/{:04x}".format(e.extracted , e.expected) , file = sys.stderr)
                    yield Skipped_record(exp_rec_no , "Bad checksum in part header" , e.extracted , e.expected)
                    log_state = 0
                    exp_rec_no += 1
                    continue
                if DEBUG:
                    print("Par Header: {}".format(part_hdr) , file = sys.stderr)
                if part_hdr[ 0 ] != exp_part_no:
                    yield Skipped_record(exp_rec_no , "Unexpected partition number" , part_hdr[ 0 ] , exp_part_no)
                    log_state = 0
                    exp_rec_no += 1
                elif part_hdr[ 2 ] != rec_hdr[ 4 ]:
                    yield Skipped_record(exp_rec_no , "Bad rewrite number" , part_hdr[ 2 ] , rec_hdr[ 4 ])
                    log_state = 0
                    exp_rec_no += 1
                elif part_hdr[ 1 ] == 0 or part_hdr[ 1 ] > part_size:
                    yield Skipped_record(exp_rec_no , "Bad partition size" , part_hdr[ 1 ] , part_size)
                    log_state = 0
                    exp_rec_no += 1
                else:
                    try:
                        part_data = ck.get_checksummed_words(part_hdr[ 1 ])
                    except Short_chunk:
                        raise Record_error("Short part data")
                    except Bad_checksum as e:
                        if DEBUG:
                            dump_words(e.words , sys.stderr)
                            print("Bad checksum in part data {:04x}/{:04x}".format(e.extracted , e.expected) , file = sys.stderr)
                        yield Skipped_record(exp_rec_no , "Bad checksum in part data" , e.extracted , e.expected)
                        log_state = 0
                        exp_rec_no += 1
                        continue
                    if DEBUG:
                        dump_words(part_data , sys.stderr)
                    parts.append((part_hdr[ 0 ] , part_hdr[ 1 ] , part_hdr[ 2 ] , part_data))
                    part_size -= part_hdr[ 1 ]
                    if part_size == 0:
                        yield (rec_hdr[ 0 ] , rec_hdr[ 1 ] , rec_hdr[ 2 ] , rec_hdr[ 3 ] , rec_hdr[ 4 ] , rec_hdr[ 5 ] , rec_hdr[ 6 ] , parts)
                        log_state = 0
                        exp_rec_no += 1
                    else:
                        exp_part_no += 1
    finally:
        ck.reserved = 0
        ck.idx = len(ck.mv) - 2
        try:
            tmp = ck.get_words(1)[ 0 ]
            if (tmp >> 8) == 251:
                print("Log: E = {}".format(tmp & 0xff))
        except Short_chunk:
            raise Record_error("No E value")

class HTI_Image:
    MAGIC=b"HTI0"
    ZERO_BIT_LEN=619
    ONE_BIT_LEN=1083
    ONE_INCH_POS=968*1024

    def __init__(self):
        self.pos = int(72.4 * self.ONE_INCH_POS)
        self.image = bytearray()
        self.image.extend(self.MAGIC)
        self.block_data = []
        self.temp_w = 0
        self.mask = 0x8000

    def word_length(self , w):
        ones = (w & 0x5555) + ((w >> 1) & 0x5555)
        ones = (ones & 0x3333) + ((ones >> 2) & 0x3333)
        ones = (ones & 0x0f0f) + ((ones >> 4) & 0x0f0f)
        ones = (ones & 0x00ff) + ((ones >> 8) & 0x00ff)
        zeros = 16 - ones;
        return zeros * self.ZERO_BIT_LEN + ones * self.ONE_BIT_LEN

    def _store_block(self):
        if self.mask != 0x8000:
            self.block_data.append(self.temp_w)
        if self.block_data:
            self.image.extend(struct.pack("<i" , len(self.block_data)))
            self.image.extend(struct.pack("<L" , self.pos))
            for w in self.block_data:
                self.image.extend(struct.pack("<H" , w))
                self.pos += self.word_length(w)
        self.block_data = []
        self.temp_w = 0
        self.mask = 0x8000

    def add_bit(self , bit):
        if bit:
            self.temp_w |= self.mask
        self.mask >>= 1
        if self.mask == 0:
            self.block_data.append(self.temp_w)
            self.temp_w = 0
            self.mask = 0x8000

    def add_17bit_word(self , w):
        m = 0x8000
        while m != 0:
            self.add_bit(w & m)
            m >>= 1
        self.add_bit(1)

    def add_deadzone(self):
        for x in range(213):
            self.add_17bit_word(0xffff)

    def add_data(self , block):
        for w in block:
            self.add_17bit_word(w)

    def add_preamble_data_csum(self , block):
        csum = sum(block) & 0xffff
        self.add_17bit_word(1)
        self.add_data(block)
        self.add_17bit_word(csum)

    def add_gap(self , size):
        self._store_block()
        self.pos += size

    def add_irg(self):
        self.add_gap(self.ONE_INCH_POS)

    def add_ipg(self):
        self.add_gap(12000)

    def write(self , out):
        self._store_block()
        out.write(self.image)
        out.write(struct.pack("<ii" , -1 , -1))

def double_print(msg , out):
    print(msg)
    if out:
        print(msg , file = out)

def main():
    parser = argparse.ArgumentParser(description='Convert a 9825 dump file into records')
    parser.add_argument("--directory" , "-d" , nargs=1 , help = "Output records as files in DIRECTORY")
    parser.add_argument("--debug" , action="store_true" , help = "Enable debugging messages")
    parser.add_argument("--hti" , type=argparse.FileType(mode = 'wb') , help = "HTI output file")
    parser.add_argument("input" , type=argparse.FileType(mode = 'rb') , help = "Dump file")
    args = parser.parse_args()

    global DEBUG
    DEBUG = args.debug

    if args.directory:
        d = args.directory[ 0 ]
        if os.path.exists(d):
            if not os.path.isdir(d):
                print("{} must be a directory".format(d) , file = sys.stderr)
                sys.exit(1)
        else:
            try:
                os.mkdir(d)
            except OSError as e:
                print("Can't create {} directory: {}".format(d , e.strerror))
    else:
        d = None

    if d:
        out = open(os.path.join(d , "manifest.txt") , "wt" , encoding = "ascii")
    else:
        out = None

    hti = HTI_Image()

    if args.hti:
        hti.add_deadzone()
        hti.add_irg()

    try:
        s = collect_strings (args.input , 1024)

        print("Total length of dump data: {}".format(len(s)))

        if DEBUG:
            dump(s , sys.stderr)

        for x in get_records(s):
            if isinstance(x , Skipped_record):
                double_print("*** Skipped record {} ***".format(x.rec_no) , out)
                print("{} (got {:04x}, expected {:04x})".format(x.msg , x.extracted , x.expected))
            else:
                rec_no , rec_asize , rec_csize , rec_type , rec_rewrite , rec_s1 , rec_s2 , parts = x
                double_print("Record no: {}".format(rec_no) , out)
                double_print("Abs size : {}".format(rec_asize) , out)
                double_print("Curr size: {}".format(rec_csize) , out)
                double_print("Type     : {}".format(rec_type) , out)
                double_print("Rewrite #: {}".format(rec_rewrite) , out)
                double_print("S1       : {:04x}".format(rec_s1) , out)
                double_print("S2       : {:04x}".format(rec_s2) , out)
                double_print("" , out)
                if out and parts:
                    rec_file = open(os.path.join(d , "rec{:03}.bin".format(rec_no)) , "wb")
                else:
                    rec_file = None
                if args.hti:
                    block = [ rec_no , rec_asize , rec_csize , rec_type , rec_rewrite , rec_s1 , rec_s2 ]
                    hti.add_preamble_data_csum(block)
                    hti.add_17bit_word(1)
                    hti.add_ipg()

                for part_no , part_size , part_rewrite , part_data in parts:
                    double_print("Part no  : {}".format(part_no) , out)
                    double_print("Part size: {}".format(part_size) , out)
                    double_print("Part rewr: {}".format(part_rewrite) , out)
                    dump_words(part_data , sys.stdout)
                    if rec_file:
                        for w in part_data:
                            rec_file.write(struct.pack(">H" , w))
                    if args.hti:
                        block = [ part_no , part_size , part_rewrite ]
                        hti.add_preamble_data_csum(block)
                        hti.add_preamble_data_csum(part_data)
                        hti.add_17bit_word(1)
                        hti.add_ipg()
                if rec_file:
                    rec_file.close()
                if args.hti:
                    hti.add_irg()
            double_print("=" * 42 , out)
            double_print("" , out)
    except Collect_error as e:
        print("String collection error: {}".format(str(e)) , file = sys.stderr)
    except Record_error as e:
        print("Record decoding error: {}".format(str(e)) , file = sys.stderr)
    if args.hti:
        hti.write(args.hti)
        args.hti.close()

if __name__ == '__main__':
    main()

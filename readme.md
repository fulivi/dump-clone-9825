HP9825 tape utilities
=====================

v1.0 - F.Ulivi - 220127

DUMP9825 and CLONE9825 are two utility programs designed for, respectively, reading and writing HP9825 tapes on a HP9845 system. They take advantage of a special mode of TACO chips to handle 9825 formatted tapes. As far as I know, HP designed this mode into the chip but never used it.

The following figure gives an overview of the general workflow of these tools.

<img src="flow.svg" alt="Workflow" height="213" width="1000" />

Acknowledgments
---------------

My special thanks go to Rik Bos for doing a lot of testing for me on real hardware. Without him these tools wouldn't exist at all.

DUMP9825
--------

This utility does a low-level dump of HP9825 tapes on a HP9845 machine.

DUMP9825 is designed to put as little stress on the tape as possible. It only moves the tape forward at slow speed. Because of this, tape must be positioned manually at the correct point before dumping.

DUMP9825 has the following workflow:

1. It runs on 9845 and dumps the entire content of a tape track into a DATA file on disk. Records with bad checksum and/or inconsistent header fields are automatically skipped.

2. DATA file is extracted from disk image (by using, for example, hpdir)

3. Extracted file is processed by conv9825 tool on PC to generate the image of all the good records on tape in various formats

4. Steps 1 to 3 can be repeated on the same tape to accumulate as much as possible good readings of records.

5. Here are some ideas about what to do with extracted image.

    - Archive it

    - Share it

    - Create a virtual tape image to be used (for example) on MAME emulator

    - Create a disk image to be used in a HP9825-connected disk drive (such as 9885). No tool for this is available yet.

    - Re-create a real HP9825 tape with a 9845 system: CLONE9825 was written for this task (see below)

    - Study binary files offline

### Required components ###

1. HP9845 system with a working T15 cassette drive

2. Mass storage expansion ROM

3. Assembly development or execution expansion ROM

4. HP98034 HPIB module

5. A real or emulated disk drive

6. A way to extract files from real/virtual disk

### Detailed instructions ###

1. Tape is to be inserted in T15 drive. It is very important that tape is positioned at the loading point (last of initial holes). DUMP9825 doesn't position the tape and REWIND command shouldn't be used because it stresses the tape and it doesn't position tape at the right spot anyway.

2. A real/virtual disk with DUMP9825 utility should be inserted into drive

3. `MASS STORAGE IS ...`

4. `LOAD "DUMP98",1`

5. The amount of allocated 30k-blocks is printed. If you need more blocks (within the available RAM of your system), stop the program, change the marked line and restart.

6. Answer the following questions from DUMP9825.

    - The track to be dumped, either 0 (A) or 1 (B)

    - The threshold for data reading, either low (0) or high (1)

    - The threshold for gap searching, either low (0) or high (1)

    - Whether counters are to be displayed (1) or not (0) when tape is being read

    - The threshold for delta-t demodulation. It defaults to 1589. This is the value used by HP9845 to read its own tapes. Experiments by Rik Bos suggest that a good value could be around 1620.

    - The name of the dump file. Make sure you have enough free space on disk for this file, it could potentially grow in size up to the amount of RAM you allocated. Also keep in mind that file is overwritten if there's already one with the same name on disk.

7. During the dump four digits are displayed in the "DISP" area at the bottom of the screen if you enabled this option. The first 2 digits report the number of correctly recovered records, the last 2 digits the total number of records.

8. The normal error code after dump is 2. It means the terminating null record was reached. Different codes mean that dumping terminated prematurely before the end.

9. Dumped data is written to disk in a DATA file. A technical note: data is read from tape and stored in a string array, where each element is up to 30k long. The DATA file is just made up of this giant array.

10. DATA file is to be processed by the conv9825 utility. Its purpose is to convert the tape image between these formats:

    - DUMP9825 format (input only)

    - MAME hti tape image (input and output)

    - XML image (input and output)

    - Directory format, where each record is stored as a binary file (output only)

    - CLONE9825 format (output only)

    Conv9825 is invoked this way:

> conv9825.py [--track n] _input-file_ _input-format_ _output-file-or-dir_ _output-format_

Input/output Format can be one of these.

- `dump` for DUMP9825 DATA file

- `hti` for HTI tape image

- `xml` for XML image

- `dir` for directory output

- `clone` for clone output

Conv9825 can be invoked multiple times on the same output `xml` or `hti` file with different input files. At each pass the tool accumulates all the good records it finds. This capability is aimed at recovering a whole tape track by doing
multiple passes when bad records are encountered during dumping.

For example:

> conv9825.py PASS1.DATA dump output.xml xml

> conv9825.py PASS2.DATA dump output.xml xml

### Ideas for future extensions ###

1. Add the possibility to start from any position of the tape and not just at record #0.

CLONE9825
---------

This utility works in the opposite direction of DUMP9825: it takes an image file and writes a tape in HP9825 format on a HP9845 system.

In the same way as DUMP9825, CLONE9825 works on a single tape track at time. To write both tracks, CLONE9825 should be run twice.

**WARNING** CLONE9825 was only tested on emulated hardware. At the moment it is not yet known how well it performs on real machines.

These steps should be followed for CLONE9825:

1. The image DATA file is to be created by using conv9825 tool. For example, to extract track 0 from a XML image invoke conv9825 this way:

> conv9825.py --track 0 _input-xml-file_ xml _output-clone-file_ clone

2. Image file is to be added to a HPI image (e.g. by using hpdir). Note that it is very important that logical record size for this file is set at 1024 bytes.
   If you use hpdir input file should have this form: `_name_.&1024.DATA` so that it is stored with correct record size in HPI image.

3. The real/virtual disk with image file and CLONE9825 utility is to be inserted into drive

4. Destination tape should be inserted into T15 drive. Write protection should be disabled, of course. Make sure that you're not going to overwrite any precious data.

5. `MASS STORAGE IS ...`

6. `LOAD "CLON98",1`

7. The amount of allocated 30k-blocks is printed. If you need more blocks (within the available RAM of your system), stop the program, change the marked line and restart.

8. Answer the following questions from CLONE9825.

    - Name of image file (defaults to "CLONE")

    - Bit duration (defaults to 1565)

    - Whether to rewind tape (1) or not (0)

9. After image file has been loaded and tape (optionally) rewound, writing to tape will start. Keep in mind that CLONE9825 will start writing selected track without asking for confirmation. Any previous data will be silently overwritten.

10. The normal way for clone9825 to terminate is with error code 1.
    Other codes mean abnormal termination. In particular, watch out for error 2 (internal buffer underflow) and error 4 (writing past end holes).

Files
-----

1. `dump9825.asm`: assembly source of dump9825

2. `dumpsr.bas`: assembly source, formatted for assembler ROM

3. `dumpls.txt`: listing from assembler ROM

4. `dump9825.bas`: BASIC part of dump9825

5. `readme.md`: This file

6. `LICENSE`: License file

7. `dump2rec.py`: Python3 utility to extract record images from dumped data

8. `conv9825.py`: Image conversion tool

9. `clone9825.asm`: assembly source of clone9825

10. `clonsr.bas`: assembly source, formatted for assembler ROM

11. `clonls.txt`: listing from assembler ROM

12. `clone9825.bas`: BASIC part of clone9825

13. `dump9825.hpi`: ready-to-use disk image of dump9825 for (real/emulated) HP9895

    The disk image has the following files:

    1. `dumpsr.DATA`: assembly source (same as `dumpsr.bas`)

    2. `DUMP25.ASMB`: assembled object module

    3. `DUMP98.PROG`: BASIC code

14. `clone9825.hpi`: ready-to-use disk image of clone9825 for (real/emulated) HP9895

    The disk image has the following files:

    1. `clonsr.DATA`: assembly source (same as `clonsr.bas`)

    2. `CLON25.ASMB`: assembled object module

    3. `CLON98.PROG`: BASIC code

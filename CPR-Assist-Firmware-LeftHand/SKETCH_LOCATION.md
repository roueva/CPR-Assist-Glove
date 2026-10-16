# Sketch file

The `.ino` here is a **snapshot**, committed each time it changes so the
flashed firmware can be recovered. The live copy is in the Arduino sketch
folder, which must be named after the file it contains:

    C:\Users\evaro\Documents\Arduino\cpr_glove_new\cpr_glove_new.ino

Edit it there and flash from the Arduino IDE/CLI pointed at that folder.
Everything else in this directory (`.cpp`/`.h`) is the tracked source of
truth and is kept in sync with that sketch folder by hand.

Edit the live copy, then copy it back here and commit. Never edit the
snapshot directly. One `.ino` per folder only — two define setup()/loop()
twice (why the tracked copies were removed in 1c1205f).

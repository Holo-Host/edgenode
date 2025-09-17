#!/bin/sh

echo "All your fakeroot are belong to us!"

# Module dependencies are calculated before buildroot compresses the modules
# so all the filenames end up being wrong. Hoping this fixes it.
/sbin/depmod -a

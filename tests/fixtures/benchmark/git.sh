#!/bin/sh
case "$1" in
  rev-parse) printf '0123456789abcdef0123456789abcdef01234567\n';;
  status) printf ' M src/face_profile.bend\n';;
  *) exit 1;;
esac

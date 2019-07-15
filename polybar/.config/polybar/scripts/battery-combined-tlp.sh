#!/bin/sh
# https://github.com/polybar/polybar-scripts/tree/master/polybar-scripts/battery-combined-tlp

# battery=$(sudo tlp-stat -b | tail -2 | head -n 1 | tr -d -c "[:digit:],.")
battery=$(sudo /usr/bin/tlp-stat -b | grep "Charge total" | tr -d -c "[:digit:],.")

echo " $battery %"

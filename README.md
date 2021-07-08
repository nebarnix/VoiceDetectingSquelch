# VoiceDetectingSquelch
A SSB or weak signal voice detecting squelch that runs on an arduino nano! 

Based on the amazing and wonderful code by Peter Bach:
https://www.instructables.com/Speech-Recognition-With-an-Arduino-Nano/

# Operational theory:
The heart of the sketch is Peter's smoothed maximum energy in the 4 pass bands + 1 ZCF 'band' detector
The variance of the bands is then detected, and the differential is taken. 

This is smoothed with an exponential filter, and a squelch is build around this level, with a tail of 1 seond on any filtered level above the set threshold. 

A buzzer and LED are also energized upon sufficient voice detection so you can be alerted to voice activity on the bands without tying the squelch signal back into the radio if you like. 

There is no normalization of the differential for the variance level(which is on the todo list), so without an AGC input stage you will find the squelch level to be slightly volume dependant, simply as the noise is volume dependant. 

A 1.5khz RC HP filter on the input using a 10nF cap and a 10k resistor in series with the arduino nano pin will reduce low frequency signal clipping and improve the performance of the algorithm.

# Test modes
* Mode 1: Hold the sql-down button at startup for o-scope mode using arduino serial plotter
* Mode 2: Hold the sql-up button at startup for band energy mode using arduino serial plotter (useful for fine tuning the equalizer to match your radio's sound characteristics)
* Boot up normally to output filtered squelch signal and set threshold level. 

# Performance:
I found that if I can understand the voice, the filter can pick it up while set to avoid false positives. If the sensitivity is set to where voice that can be heard but not copied, then false positives occur, which might be fine for some. 

It should be very noise insensitive, unless the noise is 'warbling' and contains time varying narrow band frequency content. Constant pitch noise should be rejected as should wideband noise floor changes (the slower the change the better the rejection). 

# Performance Tuning:
* Set the alpha (default 0.15) lower to weigh the current sample less, for a smoother squelch, better noise rejection, but delayed attack speed
* Set the equalizer coefficients in test mode 2 so that all bands are the same level when no signals are present. Note that ZCF is not volume specific, so set the input volume FIRST. 

# Radio Integration
## I don't want to mess with my radio AT ALL
* Plug into the headphones jack, and set the volume by entering test mode 1 (hold the sql-down button at startup) which outputs a 9khz o-scope view over serial plotter. Use this mode to set the volume, and record or mark it with a piece of tape on the dial. Make sure the signal doesn't clip (60% full scale on noise is a good place to put it)
* Reboot the arduino without the button pressed. The serial plotter will output the filtered squelch level and the set threshold level. Use the sql-up and sql-down to set the trigger level.


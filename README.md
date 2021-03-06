# VoiceDetectingSquelch
A SSB or weak signal voice detecting squelch that runs on an arduino nano! 

Based on the amazing and wonderful code by Peter Bach:
https://www.instructables.com/Speech-Recognition-With-an-Arduino-Nano/


# Operational theory:
![Image Of Schematic](https://github.com/nebarnix/VoiceDetectingSquelch/blob/main/Schematic.PNG?raw=true)

The heart of the sketch is Peter's algorithm for a fast ~8900Hz ADC routine along with a smoothed energy detector in 4 pass bands + 1 ZeroCrossingFrequency 'band'.

Using that functionality as a stand-in for an FFT, the variance of the energy within the bands is calculated with a window time of 100mS, and the differential is taken. (or opposite)

This is smoothed with an exponential filter, and a squelch is built around this result, with a tail of 1 seond on any filtered level above the set threshold. 

A buzzer and LED are also energized upon sufficient voice detection so you can be alerted to voice activity on the bands without tying the squelch signal back into the radio if you like. 

There is no normalization of the differential for the variance level(which is on the todo list), so without an AGC input stage you will find the squelch level to be slightly volume dependant, simply as the noise is volume dependant. 

A 1.5khz RC HP filter on the input using a 10nF cap and a 10k resistor in series with the arduino nano pin will reduce low frequency signal clipping and improve the performance of the algorithm.

Update: you can omit the 10k resistor if you use a 100nF pass capacitor. 

# Which Sketch?
## UPDATE - MVD appears to be more volume sensitive than MDV, so at first glance seems to work better, but MDV is far less sensitive to volume and therefore noisefloor changes. 
**Use _MDV_ unless you want to play with MVD**
~~Use MVD unless you want to play with MDV~~
* Avg->Varaince->Differentiation -> average energy vs smoother max energy showed worse detection, abandoned. 
* Max->Varaince->Differentiation -> Max filtered band energy, variance, then differentialtion is the best one
* Max->Differentiation->Varaince -> Max filtered band energy, differentiation, then variance is where I started, but the model shows it is inferior. (see below for plots)

# Hardware Needed
![Image Of Hardware Layout](https://github.com/nebarnix/VoiceDetectingSquelch/blob/main/Hardware.png?raw=true)
* An arduino nano
* Two 2.2k ADC bias resistors  Vcc---2.2k---ADCPin---2.2k----GND
* A headphones jack
* 10nF capacitor decoupling capacitor between the signal input pin from the jack and the ADC pin
* 10K resistor (OR use a 100nF cap with no resistor, but this leads to a greater source load)

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
* Plug into the headphones or external speaker jack, and set the volume by entering test mode 1 (hold the sql-down button at startup) which outputs a 9khz o-scope view over serial plotter. Use this mode to set the volume, and record or mark it with a piece of tape on the dial. Make sure the signal doesn't clip (60% full scale on noise is a good place to put it)
* Reboot the arduino without the button pressed. The serial plotter will output the filtered squelch level and the set threshold level. Use the sql-up and sql-down to set the trigger level.
* The arduino will beep on voice detection! (not really a squelch)
* Useless Power User Trick: 'Y' the signal into your PC's line-in, and use the serial port data to implement a mute/unmute function on your computer! mmm so Squelchy!

## I want to mess with my radio a little
* Find the audio stage after where the AGC is implemented but before the volume knob is applied. Use this signal (through an appropriate operational or audio amplifier stage) so that you can set the speaker volume to a comfortable level without messing up the input volume to the nano. 
* In this case the circuit is still functioning as a voice detector (BEEEP), not really a squelch. 

## My radio is my project car
* Follow above advice, but be sure to extract the audio BEFORE the squelch gate is applied!
* Find where at in the audio chain the squelch signal is injected, and inject (use a resistor!) the output of the arduino here. Usually this is a gate, so a high level means silence and a low level means audio is able to pass. 
* Drill some holes! Add an OLED display with the current squelch level on it! Add a NexTion display and plot the serial data! YOU NEED TO SHOW OFF ALL THE DATA!!

# Discussion of Algorithms
Ultimately what the program is looking for, is time varying spread of the energy in the passbands (and ZCF). Below is an example of what speech looks like among the bands, followed by the output of the algorithm before it is converted to a squelch signal. .

![Plot of MDV vs MVD](https://github.com/nebarnix/VoiceDetectingSquelch/blob/main/SpeechBands.PNG?raw=true)
![Plot of MDV vs MVD](https://github.com/nebarnix/VoiceDetectingSquelch/blob/main/MaxDiffVariance.png?raw=true)
![Plot of MDV vs MVD](https://github.com/nebarnix/VoiceDetectingSquelch/blob/main/MaxDiffVariance%20vs%20MaxVarianceDiff.png?raw=true)

There *is* a difference between the variance of the derivative and the derivative of the variances, but it is hard to say if it is mathematical or practical due to rounding errors and bit noise. I would love for someone with better statistical calculus skills to show up and comment here!

The results are close, but as you can see below in the model, taking the variance of the energy band data and then taking the derivative of that variance does result in slightly better noise rejection. See below for plots of the processing train: Note that the end of this audio recording of two CBers contains no voices after ~15 seconds. 

![Plot of MDV vs MVD](https://github.com/nebarnix/VoiceDetectingSquelch/blob/main/MaxDiffVariance%20vs%20MaxVarianceDiff%202.png?raw=true)
![Plot of MDV vs MVD](https://github.com/nebarnix/VoiceDetectingSquelch/blob/main/SqlSigsFiltered.png?raw=true)

# Future Work
* Both algorithms are inherently volume sensitive as noise is volume sensitive. Playing with an idea to keep track of max energy (non band specific) then normalize all energy band data by this number to remove this volume sensitivity. Still in work. 
* ZCF is not volume sensitive but is treated like it is. How to normalize? (maybe a looooonnnggg time constant high pass filter then re-offset by known value to match other band data?)






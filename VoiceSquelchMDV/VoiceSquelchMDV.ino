//-----------------------------------------------------------------------------
// Copyright 2021 Peter Balch
//   digital filter tester
//   subject to the GNU General Public License
//-----------------------------------------------------------------------------

#include <Arduino.h>
#include <SPI.h>
#include "Coeffs.h"
#include "digitalWriteFast.h"
#include <toneAC.h>

//-----------------------------------------------------------------------------
// Defines, constants and Typedefs
//-----------------------------------------------------------------------------

// pins
const int AUDIO_IN = A7;
const int SQLUP = 2;
const int SQLDWN = 3;

// get register bit - faster: doesn't turn it into 0/1
#ifndef getBit
#define getBit(sfr, bit) (_SFR_BYTE(sfr) & _BV(bit))
#endif

//-----------------------------------------------------------------------------
// Global Constants
//-----------------------------------------------------------------------------

//const byte NumSegments = 13;
const byte NumSegments = 1;
//const byte SegmentSize = 50; //in mS
const byte SegmentSize = 100; //in mS
const byte hyster = 2;

//works but is slow, can we disable all filtering but the final?
/*const float DeltaAlpha = 0.1;
const float ZeroDeltaAlpha = 0.1;
const float PrevAlpha = 0.5;
const float SqlAlpha = 0.5;*/

//it did work to only filter the Sql (variance) but there were occasional false alarms. Maybe we can do better
const float DeltaAlpha = 1;
  const float ZeroDeltaAlpha = 1;
  const float PrevAlpha = 1; //filtering for historical band power data
  const float SqlAlpha = 0.15;

//it did work to only filter the Sql (variance) but there were many false alarms. Maybe we can do better
/*const float DeltaAlpha = 0.75; //how much to smooth the diff band data
  const float ZeroDeltaAlpha = 0.75; //how much to smooth the zero band data because it tends to be MUCH noiser
  const float PrevAlpha = 0.75; //filtering for historical band power data
  const float SqlAlpha = 0.15;*/


//-----------------------------------------------------------------------------
// Global Variables
//-----------------------------------------------------------------------------

word CurBandData[nBand + 1]; //current band data
word PrevBandData[nBand + 1]; //current band data
float DiffBandData[nBand + 1]; //current band data
float Squelch = 0;
bool IsSquelch = false,bandTest=false;
unsigned long SqlTime = 0;
byte SqlThresh = 125;
bool clipAlarm = false;
//unsigned long time1, time2;

//-------------------------------------------------------------------------
// GetSerial
//-------------------------------------------------------------------------
byte GetSerial() {
  while ( Serial.available() == 0 ) ;
  return Serial.read();
}

//Automatic Gain Control Block (GNUradio based )
/*
float NormalizingAGC(int val, float AGC_loop_gain)
{
  static float gain = 1; //Initial Gain Value
  static char firsttime = 1;
  //float rate;
  //double attack_rate = 1e-1;
  //double decay_rate = 1e-1;
  static int zero = 512;
  const int desired = 100;
  const int max_gain = 100;
  float error;
  float result;

  //output = input * _gain;

  if (val < zero) //find the center value of the data (seems like it needs a gain of less than 1 but ok integers)
    zero--; else
    zero++;
  val = val - zero;

  //Serial.print(val);
  //Serial.print(" ");

  result = val * gain;

  error = desired - fabs(result);

  gain = gain + (AGC_loop_gain * error);

  // Not sure about this but could avoid problems
  if (gain < 0.0)
    gain = 10e-5;

  if (max_gain > 0.0 && gain > max_gain)
  {
    gain = max_gain;
  }

  //Serial.print(gain);
  //Serial.print(" 100 ");
  //Serial.print(error);
  //Serial.print(" ");
  return result+512;
}
*/
//-------------------------------------------------------------------------
// PollBands
//-------------------------------------------------------------------------
bool PollBands(bool init)
{
  //int sampleRate=0;
  bool IsPos;
  static unsigned long prevTime;
  byte band, val1, val2;
  const byte hyster = 20;
  static int zero = 500;
  //static byte curSegment = 255;
  long val;
  word zcr;
  static int valmax[10];
  static int pd[10] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
  static int ppd[10] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
  static int ppval = 0;
  static int pval = 0;
  
  //ZCR is a rate, not an energy, so it is the only NON volume dependant parameter. Can it be self-normalized?
  //const float eq[] = {0.9, 4, 2, 1.2, 1}; //equalizer - HF radio (this would be nice to auto calc somehow) 
  const float eq[] = {0.4, 4.5, 2.2, 1.2, 1}; //equalizer - FT-221R //level to shoot for is apparently ~ 100??
  //const float eq[] = {0.30, 4.5, 2.4, 1.2, 0.70}; //equalizer - FT-221R //level to shoot for is apparently ~ 160?? (or maybe just 100? does it matter?)
  //const float eq[] = {0.30, 4.5, 2.4, 1.2, 0.70}; //equalizer - Laptop SDR Audio Out //level to shoot for is apparently ~ 160?? (or maybe just 100? does it matter?)

  if (init)
  {
    memset(pd, 0, sizeof(pd));
    memset(ppd, 0, sizeof(ppd));
    memset(CurBandData, 0, sizeof(CurBandData));
    memset(PrevBandData, 0, sizeof(PrevBandData));
    memset(DiffBandData, 0, sizeof(DiffBandData));
    pval =  0;
    ppval =  0;
    return false;
  }

  val = 0;
  IsPos = true;
  

  zcr = 0;
  prevTime = 0;
  memset(valmax, 0, sizeof(valmax));
  
  prevTime = millis();
  //8850-8950 samples per second
  while (millis() - prevTime < SegmentSize)
  {
    //sampleRate++; //metric only, comment out for 
    while (!getBit(ADCSRA, ADIF)) ; // wait for ADC
    val1 = ADCL;
    val2 = ADCH;
    bitSet(ADCSRA, ADIF); // clear the flag
    bitSet(ADCSRA, ADSC); // start ADC conversion
    val = val1;
    val += val2 << 8;

    
    if(val >= 1023 || val == 0)
      clipAlarm = true;

    //fixed response averaging filter, will find the zero point. 
    if (val < zero) 
      zero--; else
      zero++;
    val = val - zero;
    
    //Too much of a performance hit  
    //val = round(NormalizingAGC(val, 0.001))-512;

    //Find the zero crossing rate using a small bit of hysterisis 
    if (IsPos)
    {
      if (val < -hyster)
      {
        IsPos = false;
        zcr++;
      }
    } else {
      if (val > +hyster)
      {
        IsPos = true;
        zcr++;
      }
    }
    ppval = pval;
    pval = val;

    for (band = 0; band < nBand; band++)
    {
      int L1, L2;
      //B side, previous OUTPUTS first
      L1 =  ((-(filt_b1[band]) * pd[band] - filt_b2[band] * ppd[band]) >> 16) + val;
      
      //now add in the A side, previous INPUTS
      L2 = (filt_a0[band] * L1 - filt_a0[band] * ppd[band]) >> 16;
      ppd[band] = pd[band];
      pd[band] = L1;
      //This is a strange but very fast way to perform a fixed response filter!
      if (abs(L2) > valmax[band]) //we're only looking for the filtered MAX energy in each band during the window!
        valmax[band]++;
    }
  }

  //All done collecting window data, apply band equalizer. 
  //time2 = micros();
  //Floating point, slow, but after data window is done, so no change to filter response timing. 
  for (band = 0; band < nBand; band++)
    CurBandData[band + 1] = round(valmax[band] * eq[band + 1]); 
  CurBandData[0] = round(zcr * eq[0]); 


  /*if (init) //initialize the previous values to keep the exp filter from reacting
    {
    for (seg = 0; seg < NumSegments; seg++) {
    for (band = 0; band <= nBand; band++) {
      PrevBandData[band] = CurBandData[band];
    }

    }
    }*/

  
    if(bandTest == true)
      {
      //Serial.print(sampleRate);Serial.print(" ");
      PrintCurBandData();
      }
    else CalcBandDeltaVar();
   
}

//-----------------------------------------------------------------------------
// PrintCurBandData
//-----------------------------------------------------------------------------
void PrintCurBandData(void)
{
  byte i, band;

  //Serial.println("a");

  for (band = 0; band <= nBand; band++) {
    Serial.print(CurBandData[band]);
    Serial.print(" ");
  }
  Serial.println("");

}

//-----------------------------------------------------------------------------
// CalcBandDeltaVar - take diff then the varaince, more computation time, seems to work less robust in matlab model
//-----------------------------------------------------------------------------
void CalcBandDeltaVar(void)
{
  byte seg, i, band;
  float accum = 0, mean, variance = 0;

  //Calculate a delta
  for (band = 0; band <= nBand; band++) {
    float difference = abs(((int)CurBandData[band] - (int)PrevBandData[band])); //squared might be better than abs?
     //should we limit loop difference?
     
    if (band == 0) //zero band is more noisey
      DiffBandData[band] = ZeroDeltaAlpha * difference + (1 - ZeroDeltaAlpha) * DiffBandData[band]; //do we filter the band or the diff or the result!? ahh
    //PrevBandData[band] = ZeroDeltaAlpha*CurBandData[band]+(1-ZeroDeltaAlpha)*PrevBandData[band]; //do we filter the band or the diff or the result!? ahh
    else
      DiffBandData[band] = DeltaAlpha * difference + (1 - DeltaAlpha) * DiffBandData[band]; //PrevBand Data is now the difference data
    //PrevBandData[band] = DeltaAlpha*CurBandData[band]+(1-DeltaAlpha)*PrevBandData[band]; //do we filter the band or the diff or the result!? ahh

    //if(band>0)
    accum += DiffBandData[band];

    //Serial.print(DiffBandData[band]);
    //Serial.print(" ");
    PrevBandData[band] = round((1 - PrevAlpha) * PrevBandData[band] + PrevAlpha * CurBandData[band]); //find the average
  }

  //Find the mean by averaging all bands together
  mean = accum / 5.0; //average
  //variance is the sum of the distances from the mean
  for (band = 0; band <= nBand; band++)
  {
    variance += abs(mean - DiffBandData[band]);
  }
  //should we limit loop variance?
  
  //Squelch = (1-0.3)*Squelch+0.3*accum; //this is a standard squelch that will favor wideband changes - TOTAL energy
  Squelch = (1 - SqlAlpha) * Squelch + SqlAlpha * variance; //variance squelch between frequency bands

  if (Squelch > SqlThresh)
    IsSquelch = true;
  else
    IsSquelch = false;
  
  //time1 = micros();
  Serial.print(Squelch);
  //Serial.print(" 0 "); //set scale to include zero
  //Serial.print(time1-time2); //how long did it take to analyze the window data? 540 microseconds
  Serial.print(" ");
  Serial.println(SqlThresh);

}

void DecSQL()
{
  if (SqlThresh < 253)
    SqlThresh++;
  delay(250);
}

void IncSQL()
{
  if (SqlThresh > 0)
    SqlThresh--;
  delay(250);
}

//-----------------------------------------------------------------------------
// testADCsimple
//-----------------------------------------------------------------------------
void testADCsimple(void)
{
  int i = analogRead(AUDIO_IN);
  //i = NormalizingAGC(i,0.1);  
  //Serial.print(NormalizingAGC(i, 0.001));
  //Serial.print(" ");
  Serial.print(i);
  Serial.println(" 0 512 1024");
  
}

//-------------------------------------------------------------------------
// setup
//-------------------------------------------------------------------------
void setup(void)
{
  bool testMode = false;
  Serial.begin(115200);
  Serial.println("SquelchMe K7PHI");
  Serial.println("Based On Speechrecog1 by Peter Balch");

  pinMode(AUDIO_IN, INPUT);
  pinMode(SQLUP, INPUT_PULLUP);
  pinMode(SQLDWN, INPUT_PULLUP);
  pinMode(LED_BUILTIN , OUTPUT);
  analogReference(INTERNAL); //1.2V better for line applications
  //analogReference(EXTERNAL); //requires 3.3V jumper and a LOUD audio channel if not using input amp/AGC
  analogRead(AUDIO_IN); // initialise ADC to read audio input
  //attachInterrupt(digitalPinToInterrupt(SQLUP), IncSQL, RISING );
  //attachInterrupt(digitalPinToInterrupt(SQLDWN), DecSQL, RISING );

  if (!digitalReadFast(SQLUP))
  {
    //Boot-up beep
    toneAC(1500); //pins 9 and 10 on a nano hooked to a buzzer
    delay(150);
    toneAC(2500); //pins 9 and 10 on a nano hooked to a buzzer
    delay(150);
    toneAC();
    testMode = true;
  }
  else if (!digitalReadFast(SQLDWN))
  {
    //Boot-up beep
    toneAC(2500); //pins 9 and 10 on a nano hooked to a buzzer
    delay(150);
    toneAC(1500); //pins 9 and 10 on a nano hooked to a buzzer
    delay(150);
    toneAC();
    bandTest = true;
  }
  else
  {
    //Boot-up beep
    toneAC(2600); //pins 9 and 10 on a nano hooked to a buzzer
    delay(50);
    toneAC();
  }



  //Serial.println("0 0 0 0 0 0 350");
  if (testMode == true)
  {
    while (1)
    {
      testADCsimple();
    }
  }

  PollBands(true);
}

//-----------------------------------------------------------------------------
// Main routines
// loop
//-----------------------------------------------------------------------------
void loop(void)
{
  static bool LEDFlag = false;

  PollBands(false);
  if(clipAlarm == true)
    {
    clipAlarm = false;
    
    //annoying and happens so often as to be useless unless selecting the frequency initially, needs to be a mode?
    //toneAC(1500,10,25,false);   //toneAC( frequency [, volume [, length [, background ]]] )
    }
  else if (IsSquelch == true)
  {
    SqlTime = millis();

    if (LEDFlag == false)
    {
      digitalWrite(LED_BUILTIN, HIGH);
      toneAC(1500);
    }

    LEDFlag = true;
  }

  if (millis() - SqlTime > 1000)
  {
    LEDFlag = false;
    digitalWrite(LED_BUILTIN, LOW);
    toneAC();
  }

  if (!digitalReadFast(SQLUP))
    IncSQL();
  else if (!digitalReadFast(SQLDWN))
    DecSQL();
}


%% Load Wav FIle
%tic;
clear all;

%Must be 10-bit 8890 sps to mirror arduino!
%hfile = 'K7EMEcall.wav';
%hfile = 'SDRSharp_20210703_012541Z_28385000Hz_AF.wav';
%hfile = 'SDRSharp_20210703_013858Z_27355000Hz_AF_8k.wav';
%hfile = 'SDRSharp_20210703_013858Z_27355000Hz_AF_8k_HPF.wav';
hfile = 'SWOT-net test data diversity rx LR_9k_hpf.wav'; %gaston (good silence) starts around 6876417

[audioData,Fs] = audioread(hfile,'native'); %SIGNED 16 bit data

%convert to 10 bits
audioDataL = int16(audioData(:,2)');
audioDataR = int16(audioData(:,1)');

audioDataL = bitsra(audioDataL,6); %shift right by 6 bits to take 16 to 10
audioDataR = bitsra(audioDataR,6); %shift right by 6 bits to take 16 to 10

%DC offset real world (not exact)
%audioDataL = audioDataL+500;
%audioDataR = audioDataR+500;

Ts = 1/(Fs);
audioTime=0:Ts:Ts*(numel(audioDataL)-1);

n=1;
fprintf(['Loaded IQ WAV file, Sample rate detected as ' num2str(Fs/1000) 'Ksps\n']);
fprintf(['Length is ' num2str(audioTime(end),3) ' seconds\n']);

%% Add noise
%add decrease in volume of noise floor
for sample = 1:numel(audioDataL)
    if audioTime(sample) > 15 && audioTime(sample) < 18
        audioDataL(sample) = audioDataL(sample) * 0.5;
    end
end


%% Spect
figure(1);
%spectrogram(audioDataL,blackman(128),60,128,1e3);
%spectrogram(audioDataL,blackman(128),[],[],Fs,'yaxis','MinThreshold',-30);
spectrogram(audioDataL(1:7:end),blackman(128),[],[],Fs/7,'yaxis');
%colormap bone
axis([0 max(audioTime) 0 6]);

%% Plot data
figure(1);
plot(audioTime,audioDataL);

%% Play result
%soundsc(audioDataL,Fs);
player = audioplayer(audioDataL, Fs,16);
play(player);

%% Apply a simple level squelch for comparison
%add squelch tail
%add filtered version as well
squelchLevel = 100;
squelchLevelOut(1:numel(audioDataL)) = 0;
for sample = 1:numel(audioDataL)
    if(mod(sample,10000) == 0)
        sample %status
    end
    
    if abs(audioDataL(sample)) > squelchLevel
        squelchLevelOut(sample) = 1;
    else
        squelchLevelOut(sample) = 0;
    end
end

plotyy(audioTime,audioDataL,audioTime,squelchLevelOut);
%% Play result
soundsc(audioDataL .* squelchLevelOut,Fs);

%% Apply a filtered level squelch for comparison
%add squelch tail

squelchLevel = 30;
squelchFLevelOut(1:numel(audioDataL)) = 0;
filtVal = 0;
filtValAlpha = 0.0005;
for sample = 1:numel(audioDataL)
    if(mod(sample,10000) == 0)
        fprintf(num2str(sample)) %status
        fprintf('\n') %status
    end
    
    filtVal = (1-filtValAlpha)*filtVal + filtValAlpha*abs(audioDataL(sample));
    
    if filtVal > squelchLevel
        squelchFLevelOut(sample) = 1;
    else
        squelchFLevelOut(sample) = 0;
    end
end

plotyy(audioTime,audioDataL,audioTime,squelchFLevelOut);
%% Play result
soundsc(audioDataL .* squelchFLevelOut,Fs);
%% Calc Band Max Energy
%(maybe average or median energy here would be better!!)
%frequencies: 150, 356, 843, 2000
clear eq val filt_a0 filt_b1 filt_b2 ppval pval L1 L2 ppd pd valavg valmax valmaxOut valavgOut
filt_a0 = int32([3259, 7166, 14089, 20190]);
filt_b1 = int32([-123690, -112214, -81133, 0]);
filt_b2 = int32([59018, 51204, 37359, 25156]);

ppval = int32(0);
pval = int32(0);
windowTime = 100e-3; %50msec
samplesPerWindow = round(windowTime / Ts);
windowSampleNum = 1;
windowNum = 1;
L1 = int32(0);
L2 = int32(0);
ppd(1:4)= int32(0);
pd(1:4)= int32(0);
valmax(1:4) = int16(0);
valavg(1:4) = int16(0);
valmaxOut(1,1:4) = int16(0);
valavgOut(1,1:4) = int16(0);
IsPos = false;
zcrHyst = 20;
zcr=0;
for sample = 1:numel(audioDataL)
    if(mod(sample,10000) == 0)
        sample %status
    end
    
    val = int32(audioDataL(sample));
    
    if (IsPos)
        if (val < -zcrHyst)   
            IsPos = false;
            zcr=zcr+1;
        end
    else
        if (val > +zcrHyst)
            IsPos = true;
            zcr=zcr+1;
        end
    end
    
    ppval = pval; %save previous and prev-previous values
    pval = val;
    
    if(windowSampleNum > samplesPerWindow)
        windowNum = windowNum+1;
        %valmaxOut(windowNum,:) = int16(double(valmax) .* eq);
        %valavgOut(windowNum,:) = int16(double(valavg) .* eq);
        %valmaxOut(windowNum,1:4) = valmax(1:4);
        %valavgOut(windowNum,1:4) = valavg(1:4);
        valmaxOut(windowNum,1) = zcr;
        valmaxOut(windowNum,2:5) = valmax;
        
        valavgOut(windowNum,1) = zcr;
        valavgOut(windowNum,2:5) = valavg;
        
        valmax(1:4) = 0;
        valavg(1:4) = int16(0);
        zcr = 0;
        windowSampleNum = 1;
        %valavg(windowNum,band) = valavg(windowNum,band)/
    end
    
    for band = 1:4
        %L1 and L2 are integers but how can you shift right a signed integer?
        %You can use the arithmetic bitsra but we should check, maybe it
        %never goes negative
        %L1 =  bitsrl(-filt_b1(band) * pd(band) - filt_b2(band) * ppd(band), 16) + val;
        L1 =  ((-filt_b1(band) * pd(band) - filt_b2(band) * ppd(band))/65536) + val;
        %L2 = bitsrl(filt_a0(band) * L1 - filt_a0(band) * ppd(band), 16);
        L2 = (filt_a0(band) * L1 - filt_a0(band) * ppd(band))/65536;
        ppd(band) = pd(band);
        pd(band) = L1;
        
        if abs(L2) > valmax(band) %Looking for the MAX VALUE during the sample window
            valmax(band) = valmax(band) + 1;
        end
        
        if abs(L2) > valavg(band)
            valavg(band) = valmax(band) + 1;
        else
            valavg(band) = valavg(band) - 1;
        end
        
    end
    windowSampleNum = windowSampleNum+1;
end
%% Apply EQ to bands and Plot Band Max Energy
clear valmaxOutEq
eq = [0.28, 4, 2, 1, 0.7]; %8khz HPF@1.5khz
%eq = [0.5, 1.5, 1, 0.8, 0.7]; %8khz
%eq = [0.4, 1.1, 0.8, 1.5, 4.5]; %44khz
%eq = [1, 1, 1, 1];
figure(2);

subplot(2,1,1);

valmaxOutEq(:,1) = double(valmaxOut(:,1)) .* eq(1);
valmaxOutEq(:,2) = double(valmaxOut(:,2)) .* eq(2);
valmaxOutEq(:,3) = double(valmaxOut(:,3)) .* eq(3);
valmaxOutEq(:,4) = double(valmaxOut(:,4)) .* eq(4);
valmaxOutEq(:,5) = double(valmaxOut(:,5)) .* eq(5);
plot(audioTime(1:samplesPerWindow:end),valmaxOutEq(:,1),audioTime(1:samplesPerWindow:end),valmaxOutEq(:,2),audioTime(1:samplesPerWindow:end),valmaxOutEq(:,3),audioTime(1:samplesPerWindow:end),valmaxOutEq(:,4),audioTime(1:samplesPerWindow:end),valmaxOutEq(:,5));
title('Maximums');
legend('zcr', 'L', 'ML', 'MH', 'H');


subplot(2,1,2);

plot(audioTime(1:samplesPerWindow:end),valavgOut(:,1)*eq(1),audioTime(1:samplesPerWindow:end),valavgOut(:,2)*eq(2),audioTime(1:samplesPerWindow:end),valavgOut(:,3)*eq(3),audioTime(1:samplesPerWindow:end),valavgOut(:,4)*eq(4),audioTime(1:samplesPerWindow:end),valavgOut(:,5)*eq(5));
title('Avgs');
legend('zcr', 'L', 'ML', 'MH', 'H');

%% calculate diffs
clear valmaxDiff valavgDiff
valmaxDiff(:,1:5) = abs(diff(double(valmaxOut)));
valmaxDiff(end+1,1:4) = 0;
valavgDiff(:,1:5) = abs(diff(double(valavgOut)));
valavgDiff(end+1,1:5) = 0;

%% Plot Diffs
figure(2)

subplot(2,1,1);

plot(audioTime(1:samplesPerWindow:end),valmaxDiff(:,1),audioTime(1:samplesPerWindow:end),valmaxDiff(:,2),audioTime(1:samplesPerWindow:end),valmaxDiff(:,3),audioTime(1:samplesPerWindow:end),valmaxDiff(:,4),audioTime(1:samplesPerWindow:end),valmaxDiff(:,5));
title('Diff of Maximums');
legend('ZCR', 'L', 'ML', 'MH', 'H');

subplot(2,1,2);

plot(audioTime(1:samplesPerWindow:end),valavgDiff(:,1),audioTime(1:samplesPerWindow:end),valavgDiff(:,2),audioTime(1:samplesPerWindow:end),valavgDiff(:,3),audioTime(1:samplesPerWindow:end),valavgDiff(:,4),audioTime(1:samplesPerWindow:end),valavgDiff(:,5));
title('Diff of Avgs');
legend('ZCR', 'L', 'ML', 'MH', 'H');

%% Calculate variance
clear valmaxDiffVar valavgDiffVar
valmaxDiffVar = var(valmaxDiff')';
valavgDiffVar = var(valavgDiff')';

%% plot variance of diffs
figure(2);
subplot(2,1,1);

plot(audioTime(1:samplesPerWindow:end),valmaxDiffVar);
title('Variance of Diff of Maximums');
%legend('L', 'ML', 'MH', 'H');

subplot(2,1,2);

plot(audioTime(1:samplesPerWindow:end),valavgDiffVar);
title('Variance of Diff of Avgs');
%legend('L', 'ML', 'MH', 'H');

%% test of variance of diffs vs diff of variances
clear valmaxVarDiff valmaxVar
figure(3);
valmaxVar = var(double(valmaxOutEq'))';
valmaxVarDiff = abs(diff(valmaxVar));
valmaxVarDiff(end+1) = 0;
plot(audioTime(1:samplesPerWindow:end),valmaxVarDiff,audioTime(1:samplesPerWindow:end),valmaxDiffVar);
legend('Max->Var->Diff', 'Max->Diff->Var');

%% smooth variances to squelches
clear SquelchMaxVarDiff SquelchMaxDiffVar

SquelchMaxVarDiff(1) = 0;
MaxVarDiffAlpha = 0.15;
SquelchMaxDiffVar(1) = 0;
MaxDiffVarAlpha = 0.15;
for window = 2:numel(valmaxVarDiff)
    SquelchMaxVarDiff(window) = (1-MaxVarDiffAlpha)*SquelchMaxVarDiff(window-1)+MaxVarDiffAlpha*valmaxVarDiff(window);
    SquelchMaxDiffVar(window) = (1-MaxDiffVarAlpha)*SquelchMaxDiffVar(window-1)+MaxDiffVarAlpha*valmaxDiffVar(window);
    
    %SquelchMaxVarDiff((samplesPerWindow*(window-1)-samplesPerWindow+1):(samplesPerWindow*(window-1)+1)) = (1-MaxVarDiffAlpha)*SquelchMaxVarDiff(window-1)+MaxVarDiffAlpha*valmaxVarDiff(window);
    %SquelchMaxDiffVar((samplesPerWindow*(window-1)-samplesPerWindow+1):(samplesPerWindow*(window-1)+1)) = (1-MaxDiffVarAlpha)*SquelchMaxDiffVar(window-1)+MaxDiffVarAlpha*valmaxDiffVar(window);
end

%% Plot Squelches
figure(4);
subplot(2,1,1);
plot(audioTime(1:samplesPerWindow:end),valmaxVarDiff,audioTime(1:samplesPerWindow:end),SquelchMaxVarDiff);
axis('tight');
title('VarDiff');
%plot(audioTime,SquelchMaxVarDiff,audioTime,valmaxVarDiff);
subplot(2,1,2);
plot(audioTime(1:samplesPerWindow:end),valmaxDiffVar,audioTime(1:samplesPerWindow:end),SquelchMaxDiffVar);
axis('tight');
title('DiffVar');
%plot(audioTime,SquelchMaxDiffVar,audioTime,valmaxDiffVar);

%% Convert Squelch to sample time from window time
% what a great time to implement the squelch tail?!
clear SquelchMaxDiffVarT SquelchMaxVarDiffT
windowSampleNum = 1;
windowNum = 1;
SMVDThresh = 95;
SMDVThresh = 95;
SquelchMaxVarDiffT(1:numel(audioDataL))=int16(0);
SquelchMaxDiffVarT(1:numel(audioDataL))=int16(0);
squelchTailMDV=0;
squelchTailMVD=0;
tailSecs = 1;
for sample = 1:numel(audioDataL)
    if windowSampleNum > samplesPerWindow
        windowNum = windowNum+1;
        windowSampleNum = 1;
    end
    
    windowSampleNum = windowSampleNum+1;
    if SquelchMaxVarDiff(windowNum) > SMVDThresh
        SquelchMaxVarDiffT(sample)=1;
        squelchTailMVD = sample+(Fs*tailSecs);
    elseif squelchTailMVD > sample
        SquelchMaxVarDiffT(sample)=1; %tail time
    end
    
    
    if SquelchMaxDiffVar(windowNum) > SMDVThresh
        SquelchMaxDiffVarT(sample)=1;
        squelchTailMDV = sample+(Fs*tailSecs);
    elseif squelchTailMDV > sample
        SquelchMaxDiffVarT(sample)=1; %tail time
    end
    
end

%% Play Result
clear audioDataSql
%"I musta 24." 0-3.5s
%"Shame on you (mumble)" 4.7-8.7s
%"with that I gotta go crack a beer" 10-11.6s
%"raider come off" ?? 13-14.17s
%player = audioplayer(audioDataL/300, Fs);

audioDataSql = audioDataL.*SquelchMaxVarDiffT; %use this to keep long silences
%audioDataSql = audioDataL(SquelchMaxVarDiffT~=0); %use this to cut out the
player = audioplayer(audioDataSql, Fs,16);

%player = audioplayer(audioDataL.*SquelchMaxVarDiffT, Fs,16);
%player = audioplayer((audioDataL).*SquelchMaxDiffVarT, Fs,16);
play(player);
%plot((audioDataL/300).*SquelchMaxVarDiffT);
%soundsc(audioDataL,Fs);
%soundsc(audioDataL .* SquelchMaxVarDiffT,Fs);
%soundsc(audioDataL .* SquelchMaxDiffVarT,Fs);

%% stop
stop(player);

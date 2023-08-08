function [ cardiac_time_data, respiration_data_interp, trigger_data, cardiac_data ] = create_FSL_physio_text_file( fname , TR, number_of_volumes )
%File takes in the pfile.physio (fname) and then outputs text file for physiological noise correction with FSL
%Function was written and tested using FSL 5.0 and MATLAB R2015b. End of
%physiological data used as the end of the output physio file. Start of
%output file equals end - total time (TR * number_of_volumes). This way the
%physiological data from any dummy scans are not included in the output
%file.

%Inputs
% fname = filename for pfile.physio
% TR = TR in seconds for each volume (i.e., sampling period of volumes)
% number_of_volumes = number of volumes collected

% Output
% FSL_pfile.physio
% Column 1 = Time
% Column 2 = Respiratory Data
% Column 3 = Scanner Triggers
% Column 4 = Cardiac Data
% Sampling rate = 100 Hz


%Initialize variables
respiration_sampling_rate = 25; %In Hz
cardiac_sampling_rate = 100; %In Hz
trigger_width = TR*0.2; %Width of trigger pulse in seconds
total_time = (TR * number_of_volumes);

%Read data
data = dlmread(fname);
[~,name,~] = fileparts(fname);

%Create cardiac data
cardiac_start = find(data==-8888,1)+1;
cardiac_data = data(cardiac_start:end,1);
cardiac_time_data = (0-((length(cardiac_data)/cardiac_sampling_rate)-(total_time))):(1/cardiac_sampling_rate):(total_time);
cardiac_time_data = cardiac_time_data(1,2:end);

%Create respiratory data
respiration_start = find(data==-9999,1)+1;
respiration_end = find(data==-8888,1)-1;
respiration_data = data(respiration_start:respiration_end,1);
respiration_time_data = (0-((length(respiration_data)/respiration_sampling_rate)-(total_time))):(1/respiration_sampling_rate):(total_time);
respiration_time_data = respiration_time_data(1,2:end);
respiration_data_interp = interp1(respiration_time_data,respiration_data,cardiac_time_data,'spline'); %Interpolate respiration data to match total_time data sampling rate

%Create trigger vector
data_collection_start = find(((cardiac_time_data.^2)-min(cardiac_time_data.^2)) == 0); %Ran into problems finding 0 cardiac_time_data index in some cases.
trigger_starts = (0:TR:total_time-TR);
trigger_data = zeros(size(cardiac_time_data));
for i=1:length(trigger_starts)
    trigger_data(floor((data_collection_start+(trigger_starts(i)*cardiac_sampling_rate)+1)):floor((data_collection_start+(trigger_starts(i)+trigger_width)*cardiac_sampling_rate))) = 1;
end


%Plot results

% ss = get(0,'screensize'); %The screen size
% width = ss(3);
% height = ss(4);
% vert = 900; %300 vertical pixels
% horz = 1800; %600 horizontal pixels
% figure()
% FigHandle = gcf;
% set(FigHandle,'Position',[(width/2)-horz/2, (height/2)-vert/2, horz, vert]);
% 
% ax1 = subplot(3,1,1);
% plot(cardiac_time_data,cardiac_data)
% title('Cardiac Data')
% xlabel('Time (s) with 0 s = start of first volume')
% ylabel('Amplitude')
% axis([min(cardiac_time_data) max(cardiac_time_data) min(cardiac_data)-(0.10*abs(min(cardiac_data))) max(cardiac_data)+(0.10*abs(max(cardiac_data)))])
% ax1 = gca;
% set(ax1,'YTickLabel',[])
% 
% ax2 = subplot(3,1,2);
% plot(cardiac_time_data,respiration_data_interp)
% title('Respiration Data')
% xlabel('Time (s) with 0 s = start of first volume')
% ylabel('Amplitude')
% axis([min(cardiac_time_data) max(cardiac_time_data) min(respiration_data)-(0.10*abs(min(respiration_data))) max(respiration_data)+(0.10*abs(max(respiration_data)))])
% ax2 = gca;
% set(ax2,'YTickLabel',[])
% 
% ax3 = subplot(3,1,3);
% plot(cardiac_time_data,trigger_data)
% title('Scanner Triggers')
% xlabel('Time (s) with 0 s = start of first volume')
% ylabel('Amplitude')
% axis([min(cardiac_time_data) max(cardiac_time_data) min(trigger_data)-(0.10*abs(min(trigger_data))) max(trigger_data)+(0.10*abs(max(trigger_data)))])
% ax3 = gca;
% set(ax3,'YTickLabel',[])
% 
% linkaxes([ax1,ax2,ax3],'x')
% 
%Combine data and write to tab delimited textfile
physio_data = [cardiac_time_data' respiration_data_interp' trigger_data' cardiac_data];
dlmwrite(strcat(name,'.txt'),physio_data,'delimiter','\t','precision',9);

exit
end


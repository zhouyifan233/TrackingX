% example_radar.m
% ====================================================>
% The following seem to be descent parameters:
%   - ProbOfDetection = 0.8
%   - ProbOfDeath = 0.2
%   - VelocityErrVariance = 2
%   - ObsErrVariance = 50
%   - ProbOfConfirm = 0.9
%   - PHD.BirthScheme = {'Expansion', 5000}
%

%% Radar specific settings
RadarName = 'staddon';
switch(RadarName)
    case('staddon')
        % Surveillance region parameters
        V_bounds = [-8154.72944624983;... % X-min | 
                    -212.289393440959;... % X-max | Surveillance region bounding
                    -7548.44272179096;... % Y-min | box coordinates (m)
                    4355.32645897434]';   % Y-max |
        RadarCoords.lat = 50.33933333;
        RadarCoords.lon = -4.12527778;
        RadarCoords.lat = 50.346069;
        RadarCoords.lon = -4.113670;
    case('longroom')
        % Surveillance region parameters
        V_bounds = [-8154.72944624983;... % X-min | 
                    3000;...              % X-max | Surveillance region bounding
                    -7548.44272179096;... % Y-min | box coordinates (m)
                    4355.32645897434]';   % Y-max |
        RadarCoords.lat = 50.36286670714617;
        RadarCoords.lon = -4.156833300366998;
end

% Load dataset
load(strcat(RadarName,'.mat'));
N = size(DataList,2); % Simulation length

%% Focus on region of high clutter
lon_lim = [-4.1538   -4.1152];
lat_lim = [50.3097   50.3373];
% Convert LLA limits to NED
[y_lim, x_lim] = geodetic2ned(lat_lim,...
                              lon_lim, ...
                              0,...
                              RadarCoords.lat,...
                              RadarCoords.lon,...
                              0,...
                              referenceEllipsoid('wgs84'));
V_bounds = [x_lim(1);... % X-min | 
            x_lim(2);... % X-max | Surveillance region bounding
            y_lim(1);... % Y-min | box coordinates (m)
            y_lim(2)]';  % Y-max |                         
for i = 1:N
    j = 1;
    while j <= size(DataList{i},2)
        if(DataList{i}(3,j)>lat_lim(2) || DataList{i}(3,j)<lat_lim(1) || DataList{i}(4,j)<lon_lim(1) || DataList{i}(4,j)>lon_lim(2))
            DataList{i}(:,j) = [];
            j = j -1;
        end
        j = j + 1;
    end
end

%% Plot & Recording settings
% Plot settings
ShowPlots = 1;              % Set to 0 to prevent showing any plots
ShowUpdate = 1;             % Set to 0 to skip showing update plots
ShowTrackInfo = 0;
NumPersistFrames = 50;           

% Recording settings
Record = 1;                 % Set to (0|1) to turn video recording (off|on)
FrameRate = 0.5;            % Number of frames per second
VideoQuality = 100;         % Set to desired quality percentage
VideoPathName = strcat(RadarName,'_heavy_clutter_staddon.avi'); % Set to the desired path and name of produced recording

%% Instantiation of necessary components

% Instantiate a Dynamic model (CV model with q = 1 m/s^2)
dyn = ConstantVelocityModelX_2D('VelocityErrVariance',1);
dyn.TimeVariant = 2;

% Instantiate an Observation model (Variance of 50m^2 on each coordinate)
obs = LinGaussObsModelX_2D('NumStateDims',4,'ObsErrVariance',100,'Mapping',[1 3]);

% Compile the State-Space model
ssm = StateSpaceModelX(dyn,obs);

V = (abs(V_bounds(2)-V_bounds(1))*abs(V_bounds(4)-V_bounds(3))); % Total area of surveillance region

% Assign PHD parameter values
config.NumParticles = 100000;
config.Model = ssm;
config.BirthIntFcn = @(Np)[abs(V_bounds(2)-V_bounds(1))*rand(1,Np)+V_bounds(1);... % Uniform position across the surveillance 
                           10*(rand(1,Np)-.5);...                                      % region.                         
                           abs(V_bounds(4)-V_bounds(3))*rand(1,Np)+V_bounds(3);... % Uniform speed between 0-9 m/s in both
                           10*(rand(1,Np)-.5)];                                        % X and Y.
config.PriorDistFcn = @ (Np) deal(config.BirthIntFcn(Np), repmat(1/Np, Np, 1)');   % Uniform position and weights.
config.BirthScheme = {'Expansion', 0.05*config.NumParticles};
config.ProbOfDeath = 0.005;                                                        % Probability of death = 0.5%
config.ProbOfDetection = 0.8;                                                      % Probability of detection = 70%
config.ResamplingScheme = 'Multinomial';                                           % Use Multinomial Resampling

% Instantiate PHD filter
myphd = SMC_PHDFilterX(config);

% Instantiate PF filter
mypf = ParticleFilterX(ssm);

% Initiate PDAF parameters
Params_pdaf.Clusterer = NaiveClustererX();
Params_pdaf.Gater = EllipsoidalGaterX(2,'ProbOfGating',0.99)';
Params_pdaf.ProbOfDetect = 0.8;
mypdaf = JointIntegratedProbabilisticDataAssocX(Params_pdaf);

% Initiate Track Initiator
config_ti.Filter = mypf;
config_ti.PHDFilter = myphd;
config_ti.ProbOfGating = 0.99;
config_ti.ProbOfConfirm = 0.9;
myti = PhdExistProbTrackInitiatorX_2(config_ti);

TrackList = [];

%% Create plot windows
if(ShowPlots)
    
    % Map plot
    figure('units','normalized','outerposition',[0 0 .5 1])
    ax(1) = gca;
    plot_google_map('Axis',ax(1),'APIKey','AIzaSyBXKujdtXRZiqya1soVS9pxBzYR4g7aGvM','Resize',3,'Scale',2,'MapType','satellite');
    axis(ax(1),[lon_lim(1) lon_lim(2) lat_lim(1) lat_lim(2)])
    %axis(ax(1),[-4.195 -4.11 50.31 50.375])
    
    % PHD Intensity plot
    figure('units','normalized','outerposition',[.5 0 .5 1])
    ax(2) = gca;
    
    plots = [];
end

%% START OF SIMULATION
% ===================>
for k=1:N
    fprintf('Iteration = %d/%d\n================>\n',k,N);

    % Extract DataList at time k
    tempDataList = DataList{k}(1:2,:);
    tempDataList( :, ~any(tempDataList,1) ) = [];
    
    % Perform Track initiation
    myti.MeasurementList = tempDataList; % New observations
    myti.PHDFilter.ClutterRate = size(myti.MeasurementList,2)/V;
    myti.TrackList = TrackList;
    myti.AssocWeightsMatrix = mypdaf.AssocWeightsMatrix;
    TrackList = myti.initiateTracks();
    
    % Process JPDAF
    mypdaf.MeasurementList = tempDataList;
    mypdaf.TrackList = TrackList;
    for j=1:numel(TrackList)
        mypdaf.TrackList{j}.Filter.predict();
    end
    mypdaf.associate();    
    mypdaf.updateTracks();
    
    tic;
    
    % Append state to target trajectories
    for j=1:numel(TrackList)
        if(isempty(TrackList{j}.Trajectory))
            TrackList{j}.Trajectory = TrackList{j}.Filter.StateMean;
        else
            TrackList{j}.Trajectory = [TrackList{j}.Trajectory, TrackList{j}.Filter.StateMean];
        end
    end
    
    % Plot update step results
    if(ShowPlots && ShowUpdate)
        
        % Delete all plots (other than map)
        for i = 1:numel(plots)
            delete(plots(i))
        end
        plots = [];
        hold on;
        
        if(size(DataList{k},2)>0)
            % Convert measurements to LLA and plot them
            [lat,lon,~] = ned2geodetic(DataList{k}(2,:),...
                                       DataList{k}(1,:),...
                                       0,...
                                       RadarCoords.lat,...
                                       RadarCoords.lon,...
                                       0,...
                                       referenceEllipsoid('wgs84'));
    %         lat = DataList{k}(3,:);
    %         lon = DataList{k}(4,:);
            plots(end+1) = plot(ax(1), lon,lat,'y*','MarkerSize', 10);
            plot(ax(1), RadarCoords.lon,RadarCoords.lat,...
                               '-s','MarkerSize',20,...
                               'MarkerEdgeColor','red',...
                               'MarkerFaceColor',[1 .6 .6]);
        end
        
        % Plot all existing tracks
        for j=1:numel(TrackList)
            
            % Convert track trajectory to LLA and plot it
            [lat,lon,~] = ned2geodetic(TrackList{j}.Trajectory(3,:),...
                                       TrackList{j}.Trajectory(1,:),...
                                       0,...
                                       RadarCoords.lat,...
                                       RadarCoords.lon,...
                                       0,...
                                       referenceEllipsoid('wgs84'));
            traj_length = size(lon,2);
            if(traj_length>NumPersistFrames)
                start = traj_length-NumPersistFrames;
            else
                start = 1;
            end
            plots(end+1) = plot(ax(1), lon(:,start:end),lat(:,start:end),'-.w','LineWidth',2);
            plots(end+1) = plot(ax(1), lon(:,end),lat(:,end),'ws','MarkerSize',15);
            
            % Convert track velocity to LLA and plot it
            [lat_vel,lon_vel,~] = ned2geodetic(TrackList{j}.Trajectory(4,end),...
                                       TrackList{j}.Trajectory(2,end),...
                                       0,...
                                       lat(:,end),...
                                       lon(:,end),...
                                       0,...
                                       referenceEllipsoid('wgs84'));
            lat_vel = lat_vel-lat(:,end);
            lon_vel = lon_vel-lon(:,end);
            
            plots(end+1) = quiver(ax(1), lon(:,end),lat(:,end),20*lon_vel,20*lat_vel,'r','LineWidth',1.5);
            speed_kmph = sqrt(TrackList{j}.Trajectory(4,end)^2+TrackList{j}.Trajectory(2,end)^2)*3.6;
            speed_knot = speed_kmph/1.852;
            
            if(ShowTrackInfo)
                plots(end+1) = text(ax(1), lon(:,end)+0.001,lat(:,end)+0.00027,strcat("Sog:",num2str(speed_knot,2)," kt"),'FontSize',8,'Color','w');
                plots(end+1) = text(ax(1), lon(:,end)+0.001,lat(:,end)-0.00027,strcat("PoE:",num2str(TrackList{j}.ProbOfExist*100,3)," %"),'FontSize',8,'Color','w');
            end
            % TODO: Convert heading and state covariance to LLA and plot them
            % [lat,lon,h] = ned2geodetic(North,East,0,50.346069,-4.113670,0,referenceEllipsoid('wgs84'));
            % h2 = plot_gaussian_ellipsoid(TrackList{j}.Filter.StateMean([1 3]), TrackList{j}.Filter.StateCovar([1 3],[1 3]),1,20,ax(1));
            % plots(end+1) = h2;
            % plots(end+1) = text(ax(1),TrackList{j}.Filter.StateMean(1)+20,TrackList{j}.Filter.StateMean(3)-5,int2str(TrackList{j}.TrackID));
            % plots(end+1) = text(ax(1),TrackList{j}.Filter.StateMean(1)+20,TrackList{j}.Filter.StateMean(3)-130,num2str(TrackList{j}.ProbOfExist,2));
        end
        
        % Add axis labels
        xlabel('Longitude')
        ylabel('Latitude')
        
        % Plot PHD Intensity
        cla(ax(2), 'reset');
        [bandwidth,density,X,Y]=kde2d(myphd.Particles([1,3],:)');
        h = surf(ax(2),X,Y,density);        
        shading interp
        colormap(ax(2), jet(3000))
        hold on;
%         if(size(myphd.MeasurementList,2)>0)
%             plot(ax(2), myphd.MeasurementList(1,:), myphd.MeasurementList(2,:), 'y*');
%         end
        if(size(tempDataList,2)>0)
            plot(ax(2), tempDataList(1,:), tempDataList(2,:), 'y*');
        end
        % Plot all existing tracks
        for j=1:numel(TrackList)
            
            % Convert track trajectory to LLA and plot it
            [lat,lon,~] = ned2geodetic(TrackList{j}.Trajectory(3,:),...
                                       TrackList{j}.Trajectory(1,:),...
                                       0,...
                                       RadarCoords.lat,...
                                       RadarCoords.lon,...
                                       0,...
                                       referenceEllipsoid('wgs84'));
            traj_length = size(lon,2);
            if(traj_length>NumPersistFrames)
                start = traj_length-NumPersistFrames;
            else
                start = 1;
            end
            plots(end+1) = plot(ax(2), TrackList{j}.Trajectory(1,start:end),TrackList{j}.Trajectory(3,start:end),'-.w','LineWidth',2);
            plots(end+1) = plot(ax(2), TrackList{j}.Trajectory(1,end),TrackList{j}.Trajectory(3,end),'ws','MarkerSize',15);
            
            plots(end+1) = quiver(ax(2), TrackList{j}.Trajectory(1,end),TrackList{j}.Trajectory(3,end),20*TrackList{j}.Trajectory(2,end),20*TrackList{j}.Trajectory(4,end),'r','LineWidth',1.5);
            speed_kmph = sqrt(TrackList{j}.Trajectory(4,end)^2+TrackList{j}.Trajectory(2,end)^2)*3.6;
            speed_knot = speed_kmph/1.852;
            
            if(ShowTrackInfo)
                plots(end+1) = text(ax(2), lon(:,end)+0.001,lat(:,end)+0.00027,strcat("Sog:",num2str(speed_knot,2)," kt"),'FontSize',8,'Color','w');
                plots(end+1) = text(ax(2), lon(:,end)+0.001,lat(:,end)-0.00027,strcat("PoE:",num2str(TrackList{j}.ProbOfExist*100,3)," %"),'FontSize',8,'Color','w');
            end
            % TODO: Convert heading and state covariance to LLA and plot them
            % [lat,lon,h] = ned2geodetic(North,East,0,50.346069,-4.113670,0,referenceEllipsoid('wgs84'));
            % h2 = plot_gaussian_ellipsoid(TrackList{j}.Filter.StateMean([1 3]), TrackList{j}.Filter.StateCovar([1 3],[1 3]),1,20,ax(1));
            % plots(end+1) = h2;
            % plots(end+1) = text(ax(1),TrackList{j}.Filter.StateMean(1)+20,TrackList{j}.Filter.StateMean(3)-5,int2str(TrackList{j}.TrackID));
            % plots(end+1) = text(ax(1),TrackList{j}.Filter.StateMean(1)+20,TrackList{j}.Filter.StateMean(3)-130,num2str(TrackList{j}.ProbOfExist,2));
        end
        %plot(ax(2), myphd.Particles(1,:), myphd.Particles(3,:), '.');
        axis(ax(2), [V_bounds]);
        str = sprintf('PHD intensity (Update)');
        xlabel(ax(2),'X position (m)')
        ylabel(ax(2),'Y position (m)')
        zlabel(ax(2),'Intensity')
        title(ax(2),str)
        view(ax(2),180,-90);
        %set(ax(2),'Ydir','reverse')
        set(ax(2),'Xdir','reverse')
        pause(0.01)
        
        % Store video frame
        if(Record)
            F(k) = getframe(ax(1));
        end
    end
    
end

% Create video file and write to it
if(Record)
    %F = F(2:end);
    vidObj = VideoWriter(char(VideoPathName));
    vidObj.Quality = VideoQuality;
    vidObj.FrameRate = FrameRate;
    open(vidObj);
    writeVideo(vidObj, F);
    close(vidObj);
end
% phd_test.m
% ====================================================>
% This is a test script which demonstrates the usage of the "SMC_PHD" class.
% 
% SETUP:
%  * Before running the simulation, open "2_crossing_targets.mat" or "3_roaming_targets.mat" datasets, from the "datasets" folder
%  * The datasets have been extracted by simulating the motion of differential robots in a 2D-plane (x,y)
%  * The "gen_obs_cluttered_multi3" function takes as an input the ground truth data, including information about the measurement noise and clutter rate
%     and then produces 1xNk cell array of corrupted and cluttered measurements, Nk being the total number of timesteps

% Load dataset
load('multiple-robot-tracking.mat');

tot_ellapsed = 0;
% Plot settings
ShowPlots = 1;              % Set to 0 to hide plots
ShowPrediction = 0;         % Set to 0 to skip showing prediction
ShowUpdate = 1;             % Set to 0 to skip showing update
SmoothTrajectories = 0;

% Recording settings
clear F;
Record = 1;                 % Set to (0|1) to turn video recording (off|on)
FrameRate = 10;            % Number of frames per second
VideoQuality = 100;         % Set to desired quality percentage
VideoPathName = 'tomb_tracks_only.avi'; % Set to the desired path and name of produced recording

lambdaV = 1; % Expected number of clutter measurements over entire surveillance region
V = 10^2;     % Volume of surveillance region (10x10 2D-grid)
V_bounds = [0 10 0 10]; % [x_min x_max y_min y_max]

% Instantiate a Transitionamic model
transition_model = ConstantVelocityX('NumDims',2,'VelocityErrVariance',0.0001);

% Instantiate a Measurement model
%measurement_model = LinearGaussianX('NumMeasDims',2,'NumStateDims',4,'MeasurementErrVariance',0.02,'Mapping',[1 3]);
measurement_model = RangeBearing2CartesianX('NumStateDims',4,'MeasurementErrVariance',[(pi/50)^2,0.02],'Mapping',[1 3]);

% Instantiate a clutter model
clutter_model = PoissonRateUniformPositionX('ClutterRate',lambdaV,'Limits',[V_bounds(1:2);V_bounds(3:4)]);

% Instantiate birth model
numBirthComponents = 10;
BirthComponents.Means = [ 1 9 9 1; 0 0 0 0; 1 1 9 9; 0 0 0 0];
BirthComponents.Covars = repmat(diag([2,0.1,2,0.1]),1,1,4);
BirthComponents.Weights = [.25, .25, .25, .25];
birth_distribution = GaussianMixtureX(BirthComponents.Means,BirthComponents.Covars, BirthComponents.Weights);
birth_model = DistributionBasedBirthModelX('Distribution', birth_distribution,...
                                           'BirthIntensity', 0.000001);

% Compile the State-Space model
ssm = StateSpaceModelX(transition_model,measurement_model,'Clutter',clutter_model, 'Birth', birth_model);

% Extract the ground truth data from the example workspace
load('example.mat');
NumIter = size(GroundTruth,2);

% Set BirthIntensity
NumTracks = 3;

% Generate DataList
meas_simulator = MultiTargetMeasurementSimulatorX('Model',ssm);
%meas_simulator.DetectionProbability = 1;
DataList = meas_simulator.simulate(GroundTruthStateSequence);

% Assign PHD parameter values
config.Model = ssm;
config.SurvivalProbability = 0.9;
config.DetectionProbability = 0.9;

% Instantiate PHD filter
filter = TrackOrientedMeMBerPoissonGMFilterX(config);
filter.Poisson.StatePosterior = copy(birth_distribution);

% Create figure windows
if(ShowPlots)
    img = imread('maze.png');
    
    % set the range of the axes
    % The image will be stretched to this.
    min_x = 0;
    max_x = 10;
    min_y = 0;
    max_y = 10;

    % make data to plot - just a line.
    x = min_x:max_x;
    y = (6/8)*x;

    figure('units','normalized','outerposition',[0 0 .5 1])
    ax(1) = gca;
    axis(ax(1), 'manual');
    figure('units','normalized','outerposition',[.5 0 .5 1])
    ax(2) = gca;
    
    axis
end

% START OF SIMULATION
% ===================>
for k=1:NumIter
    fprintf('Iteration = %d/%d\n================>\n',k,NumIter);
    
%     % Extract DataList at time k
%     tempDataList = DataList{k}(:,:);
%     tempDataList( :, ~any(tempDataList,1) ) = [];       
    
    % Change PHD filter parameters
    filter.MeasurementList = DataList(k); % New observations
    
    tic;
    % Predict PHD filter
    filter.predict();
        
    % Update PHD filter
    filter.update();
    ellapsed = toc;
    tot_ellapsed = tot_ellapsed + ellapsed;
    %fprintf("Probability of existence: %f\n", filter.ProbOfExistence);
    fprintf("Ellapsed time: %f\n\n", ellapsed);
    % Plot update step results
    if(ShowPlots && ShowUpdate)
        % Plot data
        cla(ax(1));
         % Flip the image upside down before showing it

        % NOTE: if your image is RGB, you should use flipdim(img, 1) instead of flipud.
        hold on;
        axis(ax(1),V_bounds)
        hold(ax(1),'on');

        hold(ax(1),'on');
        for i=1:filter.Bernoulli.StatePosterior.NumComponents
            if(filter.Bernoulli.StatePosterior.Weights(i)>0.8)
                means = filter.Bernoulli.StatePosterior.Trajectories{i}.StateMean;
                if SmoothTrajectories
                    means = smoothdata(means','gaussian',10)';
                end
                plot(ax(1),means(1,:),means(3,:),'.-');
                plot_gaussian_ellipsoid(filter.Bernoulli.StatePosterior.Trajectories{i}.StateMean([1,3],end),filter.Bernoulli.StatePosterior.Trajectories{i}.StateCovar([1,3],[1,3],end),'r',1,50,ax(1));
            end
        end
        
        h2 = plot(ax(1), DataList(k).Vectors(1,:),DataList(k).Vectors(2,:),'k*','MarkerSize', 10);
        str = sprintf('Robot positions (Update)');
        title(ax(1),str)
        xlabel('X position (m)')
        ylabel('Y position (m)')
            
        % Plot PHD
        cla(ax(2), 'reset');
        p = filter.Bernoulli.StatePosterior.random(100000);
        [bandwidth,density,X,Y]=kde2d(p([1,3],:)');
        %contour3(X,Y,density,50);
        h = surf(ax(2),X,Y,density);        
        shading interp
        colormap(ax(2), jet(3000))
        %set(h, 'edgecolor','none')
        hold on;
        plot(ax(2), filter.MeasurementList.Vectors(1,:), filter.MeasurementList.Vectors(2,:), 'y*');
        axis(ax(2), [V_bounds]);
        str = sprintf('PHD intensity (Update)');
        xlabel(ax(2),'X position (m)')
        ylabel(ax(2),'Y position (m)')
        zlabel(ax(2),'Intensity')
        title(ax(2),str)
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

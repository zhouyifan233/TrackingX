%% Load the ground truth data
load('multiple-robot-tracking.mat');

%% Plot settings
ShowPlots = 1;              % Set to 0 to hide plots
NumTracks = 3;

%% Model parameter shortcuts
lambdaV = 10; % Expected number of clutter measurements over entire surveillance region
V = 10^2;     % Volume of surveillance region (10x10 2D-grid)
V_bounds = [0 10 0 10]; % [x_min x_max y_min y_max]
P_D = 0.5;    % Probability of detection
timestep_duration = duration(0,0,1);

%% Models
transition_model = ConstantVelocityX('VelocityErrVariance', 0.01^2,...
                                     'NumDims', 2,...
                                     'TimestepDuration', timestep_duration);
measurement_model = LinearGaussianX('NumMeasDims', 2,...
                                    'NumStateDims', 4,...
                                    'MeasurementErrVariance', 0.1^2,...
                                    'Mapping', [1 3]);
clutter_model = PoissonRateUniformPositionX('ClutterRate',lambdaV,...
                                            'Limits',[V_bounds(1:2);...
                                                      V_bounds(3:4)]);   
detection_model = ConstantDetectionProbabilityX('DetectionProbability',P_D);

% Compile the State-Space model
model = StateSpaceModelX(transition_model,measurement_model,'Clutter',clutter_model, 'Detection', detection_model);

%% Generate DataList
meas_simulator = MultiTargetMeasurementSimulatorX('Model',model);

DataList = meas_simulator.simulate(GroundTruthStateSequence);
N = numel(DataList);

%% Base Filter
obs_covar= measurement_model.covar();
PriorState = GaussianStateX(zeros(4,1), transition_model.covar() + blkdiag(obs_covar(1,1), 0, obs_covar(2,2),0));
base_filter = KalmanFilterX('Model', model, 'StatePrior', PriorState);

%% Data Associator
config.ClutterModel = clutter_model;
config.Clusterer = NaiveClustererX();
config.Gater = EllipsoidalGaterX(2,'GateLevel',10)';
config.DetectionModel = detection_model;
assocFilter = JointIntegratedProbabilisticDataAssocX(config);

%% Metric Generators
ospa = OSPAX('CutOffThreshold',1,'Order',2);
gospa = GOSPAX('CutOffThreshold',1,'Order',2);

%% Initiate TrackList
TrackList = cell(1,NumTracks);
for i=1:NumTracks
    xPrior = [GroundTruth{1}(1,i); 0; GroundTruth{1}(2,i); 0];
    PPrior = 10*transition_model.covar();
    StatePrior = GaussianStateX(xPrior,PPrior);
    TrackList{i} = TrackX(StatePrior);
    TrackList{i}.addprop('Filter');
    TrackList{i}.Filter = copy(base_filter);
    TrackList{i}.Filter.initialise('Model',model,'StatePrior',StatePrior);
    TrackList{i}.addprop('ExistenceProbability');
    TrackList{i}.ExistenceProbability = 0.5;
end

assocFilter.TrackList = TrackList;
Logs.Pe = [];
%% START OF SIMULATION
%  ===================>

% Create figure windows
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
    subplot(2,1,1);
end

ospa_vals= zeros(N,3);
gospa_vals= zeros(N,4);
for k=2:N
    fprintf('Iteration = %d/%d\n================>\n',k,N);
    
    %% Extract DataList at time k
    MeasurementList = DataList(k);
    timestamp_km1 = DataList(k-1).Timestamp;
    timestamp_k = MeasurementList.Timestamp;
    dt = timestamp_k - timestamp_km1;
    transition_model.TimestepDuration = dt;
    fprintf('Timestamp = %s\n================>\n',timestamp_k);
    
    %% Process JPDAF
    assocFilter.MeasurementList = MeasurementList;
    assocFilter.TrackList = TrackList;
    assocFilter.predictTracks();
    assocFilter.associate();    
    assocFilter.updateTracks();
    
    %% Update target trajectories
    for t = 1: numel(assocFilter.TrackList)
        assocFilter.TrackList{t}.Trajectory(end+1) = assocFilter.TrackList{t}.Filter.StatePosterior;
        Logs.Pe(t,k) = assocFilter.TrackList{t}.ExistenceProbability;
    end
    
    %% Evaluate performance metrics
    [ospa_vals(k,1), ospa_vals(k,2), ospa_vals(k,3)] = ...
        ospa.evaluate(GroundTruthStateSequence{k},assocFilter.TrackList);
    [gospa_vals(k,1), gospa_vals(k,2), gospa_vals(k,3), gospa_vals(k,4)]= ...
        gospa.evaluate(GroundTruthStateSequence{k},assocFilter.TrackList);
    
    
     %% Plot update step results
    if(ShowPlots)
            
        subplot(3,1,1:2);
        ax(1) = gca;
        cla(ax(1));
        imagesc(ax(1), V_bounds(1:2), V_bounds(3:4), flipud(img));
        hold on;
        if(exist('data_plot','var'))
            delete(data_plot);
        end
        data_inv = measurement_model.finv(MeasurementList.Vectors);
        data_plot = plot(ax(1), data_inv(1,:), data_inv(3,:),'k*','MarkerSize', 10);

        % Plot tracks
        for j=1:numel(assocFilter.TrackList)
            means = [assocFilter.TrackList{j}.Trajectory.Mean];
            h2 = plot(ax(1), means(1,:),means(3,:),'-','LineWidth',1);
            h2 = plotgaussellipse(assocFilter.TrackList{j}.Filter.StatePosterior.Mean([1 3]),...
                                  assocFilter.TrackList{j}.Filter.StatePosterior.Covar([1 3],[1 3]),...
                                  'Color','r',...
                                  'Axis',ax(1));
            h2 = text(assocFilter.TrackList{j}.Filter.StatePosterior.Mean(1),assocFilter.TrackList{j}.Filter.StatePosterior.Mean(3), num2str(assocFilter.TrackList{j}.ExistenceProbability));
        end      
        % set the y-axis back to normal.
        str = sprintf('Target positions (Update)');
        set(ax(1), 'ydir','normal');
        title(str)
        xlabel('X position (m)')
        ylabel('Y position (m)')
        axis(ax(1), V_bounds)
        
        % Plot existence probabilities
        subplot(3,1,3);
        cla;
        for i = 1:NumTracks
            plot(1:k, Logs.Pe(i,1:k));
            hold on;
        end
        %plot(1:k,ospa_vals(1:k,1));
        title('P(E) vs Time');
        pause(0.01);        
    end
end

figure
title("OSPA");
subplot(2,2,[1 2]), plot(1:k,ospa_vals(1:k,1)), title("OSPA Metric");
subplot(2,2,3), plot(1:k,ospa_vals(1:k,2)), title("OSPA Localisation");
subplot(2,2,4), plot(1:k,ospa_vals(1:k,3)), title("OSPA Cardinality");


figure
title("GOSPA");
subplot(2,3,[1 2 3]), plot(1:k,gospa_vals(1:k,1)), title("GOSPA Metric");
subplot(2,3,4), plot(1:k,gospa_vals(1:k,2)), title("GOSPA Localisation");
subplot(2,3,5), plot(1:k,gospa_vals(1:k,3)), title("GOSPA Missed");
subplot(2,3,6), plot(1:k,gospa_vals(1:k,4)), title("GOSPA False");
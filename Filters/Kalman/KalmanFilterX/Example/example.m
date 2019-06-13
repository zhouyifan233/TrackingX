%% KalmanFilterX Demo 
% ----------------------
% * This script demonstrates the process of configuring an running a
%   KalmanFilterX object to perform single-target state estimation.
%
% * A toy single-target scenario is considered, for a target that generates
%   regular reports of it's position in the absence of clutter and/or
%   missed detection.
%
%% Extract the GroundTruth data from the example workspace
load('single-target-tracking.mat');
NumIter = size(TrueTrack.Trajectory,2);

%% Models
% Instantiate a Transitionamic model
transition_model = ConstantVelocityX('NumDims',2,'VelocityErrVariance',0.0001);

% Instantiate an Observation model
measurement_model = LinearGaussianX('NumMeasDims',2,'NumStateDims',4,'MeasurementErrVariance',0.02,'Mapping',[1 3]);
%measurement_model = RangeBearing2CartesianX('NumStateDims',4,'MeasurementErrVariance',[0.001,0.02],'Mapping',[1 3]);

% Compile the State-Space model
model = StateSpaceModelX(transition_model,measurement_model);

%% Simulation
% Data Simulator
dataSim = SingleTargetMeasurementSimulatorX(model);

% Simulate some measurements from ground-truth data
MeasurementScans = dataSim.simulate(TrueTrack);
measurements = [MeasurementScans.Vectors];

%% Initiation
% Use the first measurement scan to perform single-point initiation
measurement = MeasurementScans(1).Measurements;
timestamp = measurement.Timestamp;

% Setup prior
xPrior = measurement.Model.Measurement.finv(measurement.Vector);
PPrior = 10*transition_model.covar();
dist = GaussianDistributionX(xPrior,PPrior);
StatePrior = GaussianStateX(dist,timestamp);

% Initiate a track using the generated prior
track = TrackX(StatePrior, TagX(1));

%% Estimation           
% Instantiate a filter objects
filter = KalmanFilterX('Model',model);                            
figure;
for t = 2:NumIter
    
    % Provide filter with the new measurement
    MeasurementList = MeasurementScans(t);
    
    % Perform filtering
    prior = track.State;
    prediction = filter.predict(prior, MeasurementList.Timestamp);
    posterior = filter.update(prediction, MeasurementList);
    
    % Log the data
    track.Trajectory(end+1) = posterior;
    
    clf;
    hold on;
    meas = measurement_model.finv(measurements(:,1:t));
    true_means = [TrueTrack.Trajectory(1:t).Vector];
    track_means = [track.Trajectory(1:t).Mean];
    plot(true_means(1,1:t), true_means(3,1:t),'.-k', track_means(1,1:t), track_means(3,1:t), 'b-', meas(1,:), meas(3,:), 'rx');
    plotgaussellipse(track.Trajectory(t).Mean([1,3],1),...
                     track.Trajectory(t).Covar([1,3],[1,3]));
    legend('GroundTrouth','Estimated Mean','Measurements', 'Estimated Covariance');
    xlabel("x coordinate (m)");
    ylabel("y coordinate (m)");
    axis([2 9 1 9]);
    drawnow();
end    
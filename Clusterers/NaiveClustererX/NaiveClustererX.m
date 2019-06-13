classdef NaiveClustererX < ClustererX
% NAIVECLUSTERERX Class 
%
% Summary of NaiveClustererX:
% This is a class implementation of a naive clusterer that generates clusters 
% of tracks sharing common measurements.
%
% NaiveClustererX Properties:
%   + NumMeasDims - The number of observation dimensions.
%
% NaiveClustererX Methods:
%   + NaiveClustererX  - Constructor method
%   + cluster - Perform clustering and generate a list of clusters
%
% (+) denotes public properties/methods
%
% See also SystematicResamplerX
    properties 
    end
    
    properties (SetAccess = immutable)
        NumMeasDims
    end
    
    methods
        function this = NaiveClustererX(varargin)
        % ELLIPSOIDALGATERX Constructor method
        %   
        % Usage
        % -----
        % * nv = NaiveClustererX() returns a NaiveClustererX object
        %
        % See also NaiveClustererX/cluster
            
        end
        
        function [ClusterList,UnassocTrackInds] = cluster(this,ValidationMatrix)
        % CLUSTER Perform naive clustering to generate clusters of tracks 
        % sharing common measurements.
        %
        % Parameters
        % ----------
        % ValidationMatrix: matrix
        %   A (Nt x Nm) validation matrix, Nt being the number of tracks and 
        %   Nm being the number of measurements, where each element (t,m) is
        %   a binary variable (0 or 1), representing whether measurement m
        %   fell in the gate of target t.
        %
        % Returns
        % -------
        % ClusterList: cell vector
        %   A (1 x Nc) cell vector, where each cell represents one of Nc Cluster
        %   objects, with the following fields:
        %       - MeasIndList: A list of the indices of all measurements
        %                     contained within the cluster.
        %       - TrackIndList: A list of indices of all tracks belonging
        %                       to the cluster.
        % 
        % UnassocTrackInds: column vector
        %  A (1 x Nu) column vector, where each element contains the index
        %  (as ordered in ValidationMatrix) of any tracks that have not
        %  been associated to any measurements. As such, 0<= Nu <= Nt.
        %   
        % Usage
        % -----
        % * [ClusterList,UnassocTracks] = cluster(this,ValidationMatrix) 
        %   returns a list of clusters ClusterList and a list of unassociated
        %   track indices UnassocTracks (corresponding to the row indices of 
        %   ValidationMatrix).
        %   ClusterList is a list of Cluster objects, where each cluster
        %   object has two properties:
        %       - MeasIndList: A list of the indices of all measurements
        %                     contained within the cluster.
        %       - TrackIndList: A list of indices of all tracks belonging
        %                       to the cluster.
        %
        % See also NaiveClustererX/NaiveClustererX

            % Initiate parameters
            NumTracks = size(ValidationMatrix,1); % Number of measurements
           
            % Form clusters of tracks sharing measurements
            UnassocTrackInds = [];
            ClusterList = [];
            ClusterObj.MeasIndList = [];
            ClusterObj.TrackIndList = [];
            
            % Iterate over all tracks
            for trackInd=1:NumTracks 
                % Extract valid measurement indices
                validMeasInds = find(ValidationMatrix(trackInd,:));

                % If there exist valid measurements
                if (~isempty(validMeasInds)) 
                    
                    % Check if matched measurements are members of any clusters
                    NumClusters = numel(ClusterList);
                    matchedClusterIndFlags = zeros(1, NumClusters); 
                    for ClusterInd=1:NumClusters
                        if (sum(ismember(validMeasInds, ClusterList(ClusterInd).MeasIndList)))
                            matchedClusterIndFlags(ClusterInd) = 1; % Store matched cluster ids
                        end   
                    end

                    NumMatchedClusters = sum(matchedClusterIndFlags);
                    matchedClusterInds = find(matchedClusterIndFlags);

                    % If only matched with a single cluster, join.
                    switch(NumMatchedClusters)
                        case(1)
                            ClusterList(matchedClusterInds).TrackIndList = union(ClusterList(matchedClusterInds).TrackIndList, trackInd);
                            ClusterList(matchedClusterInds).MeasIndList = union(ClusterList(matchedClusterInds).MeasIndList, validMeasInds);
                        case(0)
                            ClusterList(end+1).TrackIndList = trackInd;
                            ClusterList(end).MeasIndList = validMeasInds;
                            %ClusterList(end+1) = ClusterObj;
                        otherwise
                            % Start from last cluster, joining each one with the previous
                            %   and removing the former.  
                            for matchedClusterInd = NumMatchedClusters-1:-1:1
                                ClusterList(matchedClusterInds(matchedClusterInd)).TrackIndList = ...
                                    union(ClusterList(matchedClusterInds(matchedClusterInd)).TrackIndList, ...
                                        ClusterList(matchedClusterInds(matchedClusterInd+1)).TrackIndList);
                                ClusterList(matchedClusterInds(matchedClusterInd)).MeasIndList = ...
                                    union(ClusterList(matchedClusterInds(matchedClusterInd)).MeasIndList, ...
                                        ClusterList(matchedClusterInds(matchedClusterInd+1)).MeasIndList);
                                ClusterList(matchedClusterInds(matchedClusterInd+1)) = [];
                            end
                            % Finally, join with associated track.
                            ClusterList(matchedClusterInds(matchedClusterInd)).TrackIndList = ...
                                union(ClusterList(matchedClusterInds(matchedClusterInd)).TrackIndList, trackInd);
                            ClusterList(matchedClusterInds(matchedClusterInd)).MeasIndList = ...
                                union(ClusterList(matchedClusterInds(matchedClusterInd)).MeasIndList, validMeasInds);
                    end
                else
                    ClusterList(end+1).TrackIndList = trackInd;
                    ClusterList(end).MeasIndList = [];
                    %ClusterList(end+1) = ClusterObj;
                    UnassocTrackInds = [UnassocTrackInds trackInd];
                end
                this.ClusterList = ClusterList;
                this.UnassocTrackInds = UnassocTrackInds;
            end
        end
    end
end


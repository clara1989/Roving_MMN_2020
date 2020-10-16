%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%         ME125 (Roving MMF) SOURCE-LEVEL ANALYSIS
% NON-PARAMETRIC CLUSTER-BASED RANDOM PERMUTATION TESTING
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%


%%% PSF PATHS %%%
% addpath('/Users/mq20096022/Documents/Matlab/fieldtrip-20200409/')
% cd('/Users/mq20096022/Documents/Students/Hannah/MAtlab_March_2020/Group_test/') %top level folder with all sub folders
% addpath(genpath('/Users/mq20096022/Documents/GitHub/MQ_MEG_Scripts-master'))
% addpath('/Users/mq20096022/Documents/Students/Hannah/MAtlab_March_2020')
% mri                 = '/Users/mq20096022/Documents/Matlab/fieldtrip-20200409/template/anatomy/single_subj_T1.nii'; % standard brain from the MNI database
% path_to_MRI_library = '/Users/mq20096022/Documents/GitHub/MEMES-master/database_for_CHILD_MEMES';

%% 1. Add Fieldtrip and MQ_MEG_Scripts to your MATLAB path + other settings
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 30/04/20: Changed paths from PSF to HR

close all

cd('/Users/42450500/OneDrive - Macquarie University/phd/data/MEG/ME175/inUse/subjects')

addpath ('/Users/42450500/Documents/MATLAB/fieldTrip/fieldtrip-20200409/'); % change path if necessary
addpath(genpath('/Users/42450500/Documents/MATLAB/fieldTrip/MQ_MEG_Scripts-master'))
addpath(genpath('/Users/42450500/OneDrive - Macquarie University/phd/other/projects/ME175/analysis/fieldTrip_scripts/stats/source_level/centroid_PFS'))
addpath ('/Users/42450500/OneDrive - Macquarie University/phd/data/MEG/ME175/inUse/subjects')

mri = ['/Users/42450500/Documents/MATLAB/fieldTrip/fieldtrip-20200409/'...
    'template/anatomy/single_subj_T1.nii']; % standard brain from the MNI database

path_to_MRI_library = ['/Users/42450500/Documents/MATLAB/fieldTrip/'...
    'database_for_MEMES_child'];

global ft_default
ft_default.spmversion = 'spm12'; % Force SPM12, SPM8 doesn't go well with mac + 2017b
ft_defaults % This loads the rest of the defaults


%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% 2. Start the subject loop - NOT AGE SPLIT! Creating VEs for each subject
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

orig    = cd;
folders = dir('3*');

for j=1:length(folders)
    cd([orig,'/',folders(j).name])
    
    % Load relevent info
    disp('Loading relevant data');
    load('deviant.mat');
    load('standard.mat');
    load('headmodel.mat');
    load('sourcemodel3d.mat');
    load('grad_trans.mat');
    load('MEMES_output.mat');
    
    %% Prepare VE points
    
    % Here we are loading the MRI chosen during MEMES coreg (ages 2-5 to 7-5)
    load([path_to_MRI_library '/' MEMES_output.MRI_winner...
        '/mri_realigned.mat']);
    
    % Transform this MRI based on the two matrices computed during MEMES coreg
    mri_realigned = ft_transform_geometry(MEMES_output.fid_matrix,...
        mri_realigned);
    mri_realigned = ft_transform_geometry(MEMES_output.trans_matrix,...
        mri_realigned);
    
    % Make a figure to check you've marked LPA and RPA the right way round(!)
    ft_determine_coordsys(mri_realigned, 'interactive', 'no');
    hold on; % add the subsequent objects to the figure
    drawnow; % workaround to prevent some MATLAB versions (2012b and 2014b) from crashing
    ft_plot_vol(headmodel);
    ft_plot_sens(grad_trans);
    
    % templates_dir      =
    % '/Users/mq20096022/Documents/Matlab/fieldtrip-20200409/template/sourcemodel/'; % PS path
    templates_dir        = '/Users/42450500/Documents/MATLAB/fieldTrip/fieldtrip-20200409/template/sourcemodel/';
    temp                 = load([templates_dir, '/standard_sourcemodel3d5mm']); %/Users/42450500/Documents/MATLAB/fieldTrip/fieldtrip-20200213/template/sourcemodel
    template_sourcemodel = temp.sourcemodel;
    template_sourcemodel = ft_convert_units(template_sourcemodel, 'mm');
    
    cfg                = [];
    cfg.grid.warpmni   = 'yes';
    cfg.grid.template  = template_sourcemodel; % standard sourcemodel
    cfg.grid.nonlinear = 'yes';
    cfg.mri            = mri_realigned; % individual mri
    sourcemodel        = ft_prepare_sourcemodel(cfg); % creates individual sourcemodel
    % (the grid points map 1-to-1 onto the template grid points, with the .pos field
    % specifying the actual coordinates of these grid points in subject space)
    sourcemodel        = ft_convert_units(sourcemodel,'mm');
    
    figure;
    ft_plot_sens(grad_trans, 'style', '*b'); % plot the MEG sensor locations
    ft_plot_vol(headmodel, 'edgecolor', 'cortex'); alpha 0.4; % plot the single shell (i.e. brain shape)
    ft_plot_mesh(sourcemodel.pos(sourcemodel.inside,:)); % plot all vertices (ie. grid points) that are inside the brain
    
    %% Prepare Leadfield
    cfg            = [];
    cfg.grad       = grad_trans;
    cfg.headmodel  = headmodel; % individual headmodel (from coreg)
    cfg.reducerank = 2; % Should check this is appropriate - also check the rank of the data as we project out mouth artifacts earlier
    cfg.channel    = deviants.label; % use the actual channels present in our data (i.e. ensure that rejected sensors are also removed here)
    cfg.grid       = sourcemodel; % individual sourcemodel (warped from template grid)
    grid           = ft_prepare_leadfield(cfg); % sourcemodel + leadfield
    %lf = grid;  % computes the forward model for many dipole locations on a regular sourcemodel and stores it for efficient inverse modelling
    
    % make a figure of the single subject{i} headmodel, and grid positions
    figure; hold on;
    ft_plot_vol(headmodel,  'facecolor', 'cortex', 'edgecolor', 'none');alpha 0.5; camlight;
    ft_plot_mesh(grid.pos(grid.inside,:),'vertexsize',20);
    ft_plot_sens(grad_trans, 'style', 'r*','edgealpha',0.3); view([90,90]);
    print('lf_headmodel_sens','-dpng','-r100');
    
    %% Compute covariance matrix
    cfg                  = [];
    cfg.covariance       = 'yes';
    cfg.vartrllength     = 2;
    cfg.covariancewindow = [0 0.5];
    avg_deviant          = ft_timelockanalysis(cfg,deviants);
    avg_standard         = ft_timelockanalysis(cfg,standards);
    
    % Make a dummy variable with covariance matrices averaged
    avg_combined     = avg_deviant;
    avg_combined.cov = (avg_deviant.cov+avg_standard.cov)./2;
    
    %% Source reconstruction
    % perform source reconstruction using the lcmv method
    cfg                   = [];
    cfg.channel           = deviants.label;
    cfg.grad              = grad_trans;
    cfg.method            = 'lcmv';
    cfg.grid              = grid;
    cfg.headmodel         = headmodel;
    cfg.lcmv.keepfilter   = 'yes';
    cfg.lcmv.fixedori     = 'yes';
    cfg.lcmv.projectnoise = 'yes';
    %cfg.lcmv.weightnorm    = 'nai';
    cfg.lcmv.lambda       = '5%';
    sourceall             = ft_sourceanalysis(cfg, avg_combined);
    
    % Now do source analysis for deviant and standard trials using the common
    % filter.
    %cfg.lcmv.filter        = sourceall.avg.filter;
    
    % This will probably end up with the same filter as for sourceall.. so I
    % can skip?
    % source_deviant         = ft_sourceanalysis(cfg, avg_deviant);
    % source_standard      = ft_sourceanalysis(cfg, avg_standard);
    
    
    % Load Atlas (contains parcellation of brain into regions/tissues/parcels)
    % atlas =
    % ft_read_atlas(fullfile('/Users/mq20096022/Documents/Matlab/fieldtrip-20200409/template/atlas/aal', 'ROI_MNI_V4.nii')); % PS path
    atlas = ft_read_atlas(fullfile('/Users/42450500/Documents/MATLAB/fieldTrip/fieldtrip-20200409/template/atlas/aal', 'ROI_MNI_V4.nii'));
    
    
    atlas = ft_convert_units(atlas, 'mm');% ensure that atlas and template_sourcemodel are expressed in the same units
    
    % Interpolate the atlas onto template sourcemodel (10mm grid),
    % because the atlas may not be at the same resolution as your grid
    % (e.g. you created a grid with 6000 vertices, but atlas may only have 2000 vertices)
    cfg              = [];
    cfg.interpmethod = 'nearest';
    cfg.parameter    = 'tissue';
    atlas_interpo    = ft_sourceinterpolate(cfg, atlas, template_sourcemodel);
    
    
    % Define our ROIs (can combine multiple parcels together to form one ROI)
    ROIs = {{'Frontal_Inf_Oper_L';'Frontal_Inf_Tri_L'},{'Frontal_Inf_Oper_R';'Frontal_Inf_Tri_R'},...
        {'Temporal_Sup_L'},{'Temporal_Sup_R'},{'Heschl_L'},{'Heschl_R'}};
    
    % Frontal merged for IFG
    % Temporal_Sup_L = STG
    % Heschl = A1
    
    ROIs_label = {'LIFG','RIFG','LSTG','RSTG','LA1','RA1'}; %Labels for the groupings
    
    %% centroid
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%create_virtual_sensor_Centroid appropriate
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%labels - can do dynamically
    for k = 1:length(ROIs)
        ROI_name = ROIs_label{k};
        
        % for this ROI, find a list of vertices that belong to it, and
        % extract the spatial filter for each vertex in cue window & target window
        vertices_all = []; % will hold a single list of all vertices (from all parcels belonging to this ROI)
        for j = 1:length(ROIs{k})
            indx         = find(ismember(atlas_interpo.tissuelabel, ROIs{k}{j})); % find index of the required tissue label
            vertices     = find(atlas_interpo.tissue == indx); % find vertices that belong to this tissue label
            % add vertices from the current parcel to the overall list
            vertices_all = [vertices_all; vertices];
        end
        % for each vertex, get the spatial filter (i.e. set of weights) for it
        vertices_filters = cat(1, sourceall.avg.filter{vertices_all});
        %vertices_filters_target = cat(1, source_standard.avg.filter{vertices_all});
        
        
        % create virtual sensor for this ROI in cue window
        VE_S = create_virtual_sensor_Centroid(ROI_name, vertices_all, vertices_filters, avg_combined, avg_standard, 1, headmodel, sourcemodel);
        VE_D = create_virtual_sensor_Centroid(ROI_name, vertices_all, vertices_filters, avg_combined, avg_deviant, 1, headmodel, sourcemodel);
        
        if ~isempty(VE_S) % successful
            ROI_activity_standard.(ROI_name) = VE_S;
        else
            fprintf(['No solution for ', ROI_name, ' in cue window.']);
        end
        
        if ~isempty(VE_D) % successful
            ROI_activity_deviant.(ROI_name) = VE_D;
        else
            fprintf(['No solution for ', ROI_name, ' in cue window.']);
        end
        
    end
    
    % VE = [];
    % VE.label = labels;
    % try
    %     VE.sampleinfo = data_clean.sampleinfo;
    % catch
    %     disp('No sampleinfo field');
    % end
    % VE.time  = data_clean.time;
    %
    %
    % % For every VE...
    % for i = 1:length(labels)
    %     fprintf('ROI: %10s done\n',labels{i});
    %     % Create VE using the corresponding filter
    %     for trial=1:(length(data_clean.trial))
    %         % Multiply the filter with the data for each trial
    %         VE.trial{trial}(i,:) = sourceall.avg.filter{i,1}(:,:)...
    %             *data_clean.trial{trial}(:,:);
    %     end
    % end
    %save(ROI_output_file, 'ROI_activity');
    
    
    %%%%%%%%%%%%%%%%%%BROKEN ABOVE
    %%%%%%
    
    %     %% Now create VEs using the computed filters
    %     labels = {'L_A1','R_A1','L_STG','R_STG','L_IFG','R_IFG'};
    %
    %     [VE_deviant]    = mq_create_VE(deviants,source_deviant,labels);
    %     [VE_standard] = mq_create_VE(standards,source_standard,labels);
    %
    %     disp('Saving data');
    %     save VE_deviant VE_deviant
    %     save VE_standard VE_standard
    
    
    %% Now produce VE plot for 6 ROIs
    % % Timelock analysis
    % cfg             = [];
    % VE_deviant_ERF  = ft_timelockanalysis(cfg,VE_deviant);
    % VE_standard_ERF = ft_timelockanalysis(cfg,VE_standard);
    
    % Get max value for all ROIs for consistent plotting
    % ylimmm = max([max(max(abs(VE_deviant_ERF.avg))) ...
    %     max(max(abs(VE_standard_ERF.avg)))]).*1.1;
    
    
    labels = fields(ROI_activity_deviant);
    for i = 1:length(labels)
        
        minyd(i) = min(min(min(ROI_activity_deviant.(labels{i}).avg)));
        maxyd(i) = max(max(max(ROI_activity_deviant.(labels{i}).avg)));
        
        minys(i) = min(min(min(ROI_activity_standard.(labels{i}).avg)));
        maxys(i) = max(max(max(ROI_activity_standard.(labels{i}).avg)));
        
    end
    
    maxy = max([maxyd;maxys])+0.3*max([maxyd;maxys]);
    miny = min([minyd;minys])-abs(0.3*min([minyd;minys]));
    
    % Plot the Figure
    figure;
    set(gcf, 'Position',  [100, 100, 800, 1600])
    % For each ROI
    limit_idx = [sort(repmat([1:2:length(labels)]',2,1)) sort(repmat([2:2:length(labels)]',2,1))];
    
    
    for i = 1:length(labels)
        
        cfg            = [];
        cfg.channel    = labels{i};
        cfg.linewidth  = 6;
        %     cfg.ylim       = [miny(limit_idx(i,1)) maxy(limit_idx(i,2))];
        cfg.xlim       = [-0.1 0.4];
        cfg.showlabels = 'yes';
        %cfg.graphcolor      = [0 0 0;1/255*[190,190,190]];
        cfg.fontsize   = 6;
        cfg.parameter  = 'avg';
        subplot(3,2,i);
        ft_singleplotER(cfg,ROI_activity_deviant.(labels{i}),ROI_activity_standard.(labels{i})); % blue = deviant
        
        xlabel('Time (sec)');
        set(gca,'fontsize', 14);
        legend('deviant','standard')
        
        % Give the title
        title(sprintf('%s',labels{i}),'Interpreter', 'none','FontSize',18);
    end
    
    % Save this png
    print(['/Users/42450500/OneDrive - Macquarie University/phd/data/MEG/ME175/inUse/group/png','/VE_ERF_MMF'],'-dpng','-r200');
    %     print('/VE_ERF_MMF','-dpng','-r200');
    
    
    close all
    
    VE_standard = [];
    VE_deviant  = [];
    
    VE_standard.time   = ROI_activity_standard.LIFG.time;
    VE_standard.dimord = ROI_activity_standard.LIFG.dimord;
    
    VE_deviant.time   = ROI_activity_deviant.LIFG.time;
    VE_deviant.dimord = ROI_activity_deviant.LIFG.dimord;
    
    for i=1:length(ROIs_label)
        
        VE_standard.label{i} = ROIs_label{i};
        VE_standard.avg(i,:) = ROI_activity_standard.(ROIs_label{i}).avg;
        
        VE_deviant.label{i} = ROIs_label{i};
        VE_deviant.avg(i,:) = ROI_activity_deviant.(ROIs_label{i}).avg;
        
        save VE_standard VE_standard
        save VE_deviant VE_deviant
    end
    cd(orig)
end


%% 3. Grand average VE (BY AGE GROUP)

% AGE GROUPS
cd ('/Users/42450500/OneDrive - Macquarie University/phd/data/MEG/ME175/inUse/subjects')

group.older   = {'3105' '3149' '3153' '3154' '3159' '3160' '3163' '3164' '3186' '3210' '3241' '3257' '3265' '3269' '3278' '3281' '3282' '3284' '3285'};
group.younger = {'3138' '3148' '3156' '3158' '3161' '3190' '3193' '3198' '3199' '3214' '3217' '3261' '3262' '3266' '3267' '3277' '3279' '3283'};

group_list = {'younger','older'};

%% source analysis (separately for young & old)

orig = cd;
folders = dir('3*');

for q=1:length(group_list)
    
    disp('Now performing group analysis by age group');
    
    idx   = find(ismember({folders.name},group.(group_list{q})));
    
    % Load the data for all subjects into two arrays
    % Put all of the VEs into a structure: Virtual electrode for deviant, and standard,
    % (avg across all subjects)
    
    VE_deviant_all  = [];
    VE_standard_all = [];
    
    for sub=1:length(idx)
        
        disp(folders(idx(sub)).name);
        cd(folders(idx(sub)).name);
        
        load('VE_deviant.mat'); % load each individual's VE D & S, and add to the '..._all' variable
        load('VE_standard.mat');
        
        VE_deviant_all{sub}  = VE_deviant;
        VE_standard_all{sub} = VE_standard;
        
        clear VE_deviant VE_standard % not sure this is necessary, it will be overwritten by next load (?)
        cd(orig)
        
    end
    
    % Grandaverage BUT keep the individuals (so we can plot 95% confidence
    % intervals
    cfg                  = [];
    cfg.parameter        = 'avg';
    cfg.keepindividual   = 'yes';
    VE_deviant_grandavg  = ft_timelockgrandaverage(cfg,VE_deviant_all{:});
    VE_standard_grandavg = ft_timelockgrandaverage(cfg,VE_standard_all{:});
    
    
    
    %% Plot S, D and difference waveform
    
    cfg           = [];
    cfg.operation = 'subtract';
    cfg.parameter = 'individual';
    MMF_all       = ft_math(cfg,VE_deviant_grandavg,VE_standard_grandavg);
    
% % % %     save (['/Users/42450500/OneDrive - Macquarie University/phd/data/MEG/ME175/inUse/group/variables/','MMF_all_',group_list{q}],'MMF_all')
% % % %     
% % % %     mask_param_all = [];
% % % %     
% % % %     cmap_1 = [0.3294 0.6706 0.3569];
% % % %     
% % % %     figure;
% % % %     set(gcf, 'Position',  [100, 100, 800, 1600]);
% % % %     
% % % %     subplots = [1 2 5 6 9 10];
% % % %     
% % % %     for i = 1:length(labels)
% % % %         % Calculate mean and 95% confidence intervals for deviants
% % % %         [mean_MMF, CI_MMF] = mq_get_confidence_cousineau(squeeze(...
% % % %             MMF_all.individual(:,i,:)));
% % % %         cfg                  = [];
% % % %         cfg.channel          = VE_deviant_all{1,1}.label{i};
% % % %         cfg.latency          = [0 0.5];
% % % %         %cfg.dim             = VE_deviant_all{1,i}.dim;
% % % %         cfg.method           = 'montecarlo';
% % % %         cfg.statistic        = 'ft_statfun_depsamplesT';
% % % %         cfg.parameter        = 'avg';
% % % %         cfg.correctm         = 'cluster';
% % % %         cfg.computecritval   = 'yes';
% % % %         cfg.numrandomization = 2000;  % NB. Only did 1000 for the sensor level. More computationally difficult to do >1000 for sensor-lvl since more channels to process. Can do way more for source.
% % % %         %cfg.clusteralpha    = 0.001;
% % % %         cfg.tail             = 0;    % Two sided testing
% % % %         cfg.alpha            = 0.05;
% % % %         % Design Matrix
% % % %         nsubj           = length(VE_deviant_all);
% % % %         cfg.design(1,:) = [1:nsubj 1:nsubj];
% % % %         cfg.design(2,:) = [ones(1,nsubj) ones(1,nsubj)*2];
% % % %         cfg.uvar        = 1; % row of design matrix that contains unit variable (in this case: subjects)
% % % %         cfg.ivar        = 2; % row of design matrix that contains independent variable (the conditions)
% % % %         %
% % % %         stat            = ft_timelockstatistics(cfg,VE_deviant_all{:},...
% % % %             VE_standard_all{:});
% % % %         %     cfg = [];
% % % %         %     cfg.parameter = 'stat';
% % % %         %     cfg.maskparameter = 'mask';
% % % %         %     cfg.linewidth = 4;
% % % %         %     subplot(3,2,i);ft_singleplotER(cfg,stat)
% % % %         %     ylabel('T-value');
% % % %         %     xlabel('Time (s)');
% % % %         %     title(sprintf('%s',labels{i}),'Interpreter', 'none','FontSize',18);
% % % %         %     set(gca,'FontSize',14);
% % % %         % This creates a line with the significant times for plotting (plotted at
% % % %         % -1.9e-13)
% % % %         mask_param                = double(stat.mask);
% % % %         mask_param(mask_param==0) = NaN;
% % % %         %         mask_param(mask_param==1) = -1.4e-13;
% % % %         mask_param(mask_param==1) = -.9e-13;
% % % %         mask_param_all(i,:) = mask_param;
% % % %         % Plot using boundedline
% % % %         subplot(6,2,subplots(i)+2);boundedline(x,mean_MMF,CI_MMF(2,:),...
% % % %             'alpha','transparency',0.3,'cmap',cmap_1);
% % % %         % Label and adjust lims
% % % %         if i>4
% % % %             xlabel('Time (sec)');
% % % %         end
% % % %         
% % % %         if logical(mod(i,2))
% % % %             ylabel('Amplitude (Tesla/cm^{2})');
% % % %         end
% % % %         
% % % %         %     ylim([-1.5e-13 1.5e-13]);
% % % %         % %     ylim([-1e-13 1e-13]);
% % % %         xlim([-0.01 0.51]);
% % % %         %yticks([-1e-13 0 1e-13])
% % % %         % Adjust FontSize
% % % %         set(gca,'fontsize', 14);
% % % %         % Give the subplot a title (ROI)
% % % %         %title(sprintf('%s',labels{i}),'Interpreter', 'none','FontSize',18);
% % % %         % Plot a line indicating the significant times computed earlier
% % % %         hold on; drawnow;
% % % %         plot([0:.001:0.5],mask_param,'-k','LineWidth',3);
% % % %         ax = gca;
% % % %         ax.YRuler.TickLabelFormat = '%.0f';
% % % %         % end
% % % %         %
% % % %         % print('MMN_VE_all2','-dpng','-r300');
% % % %         %% Plot Deviant and Standard with output from Statistics
% % % %         % colors
% % % %         cmap_2 = [0.9020 0.0824 0.2706; 0.3098 0.1686 1.0000];
% % % %         labels = {'Left_IFG','Right_IFG','Left_STG','Right_STG','Left_A1','Right_A1'};
% % % %         % mask_param_all2 = mask_param_all.*(-2.4e-13 / -1.4000e-13);
% % % %         %mask_param_all2 = mask_param_all.*(-2.2e-13 / -2.2000e-13);
% % % %         %figure;
% % % %         set(gcf, 'Position',  [100, 100, 800, 1600]);
% % % %         % For every ROI
% % % %         %for i = 1:length(labels)
% % % %         % Calculate mean and 95% confidence intervals for deviants
% % % %         [mean_deviant, CI_deviant] = mq_get_confidence_cousineau(squeeze(...
% % % %             VE_deviant_grandavg.individual(:,i,:)));
% % % %         
% % % %         % Calculate mean and 95% confidence intervals for standards
% % % %         [mean_standard, CI_standard] = mq_get_confidence_cousineau(squeeze(...
% % % %             VE_standard_grandavg.individual(:,i,:)));
% % % %         
% % % %         %     %FIX ME HERE &&&&&&
% % % %         %     % Plot using boundedline
% % % %         %     subplot(6,2,subplots(i));boundedline(x,mean_deviant,CI_deviant(2,:),...
% % % %         %         x,mean_standard,...
% % % %         %         CI_standard(2,:),'alpha','transparency',0.3,'cmap',cmap_2);
% % % %         
% % % %         subplot(6,2,subplots(i));plot(x,mean_standard,x,mean_deviant);
% % % %         % Label and adjust lims
% % % %         %xlabel('Time (sec)');
% % % %         if logical(mod(i,2))
% % % %             ylabel('Amplitude (Tesla/cm^{2})');
% % % %         end
% % % %         
% % % %         %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% % % %         %%%%%%%%%%%%%%% Y LIMITS FOR EACH ROI %%%%%%%%%%%%%%%%%%%%
% % % %         %         ylim([-10e-5 5e-5]);
% % % %         limits = {([-9e-6 8e-6]),([-9e-6 8e-6]),([-3e-5 2e-5]),([-3e-5 2e-5]),([-10e-5 6e-5]),([-10e-5 6e-5])};
% % % %         ylim(limits{i});
% % % %         %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% % % %         %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% % % %         
% % % %         xlim([0 0.51]);
% % % %         % Adjust FontSize
% % % %         set(gca,'fontsize', 14);
% % % %         % Give the subplot a title (ROI)
% % % %         title(sprintf('%s',labels{i}),'Interpreter', 'none','FontSize',18);
% % % %         % Plot a line indicating the significant times computed earlier
% % % %         hold on; drawnow;
% % % %         plot(0:.001:0.5,mask_param_all(i,:),'-k','LineWidth',3);
% % % %         ax = gca;
% % % %         ax.YRuler.TickLabelFormat = '%.0f';
% % % %     end
% % % %     
% % % %     print(['/Users/42450500/OneDrive - Macquarie University/phd/data/MEG/ME175/inUse/group/png/', group_list{q},'_VE_S-D-MMF'],'-dpng','-r300');
% % % %     
    %%     Plot S v D
    
    %cd('/Users/42450500/Desktop/phd_data/ME175_optimum/include/group/source-level');
    
    
    mask_param_all = [];
    cmap   = [0.9020 0.0824 0.2706; 0.3098 0.1686 1.0000];

    x = VE_deviant_grandavg.time;
    
    % colors
    labels = {'Left IFG','Right IFG','Left STG','Right STG','Left A1','Right A1'};
    
    figure;
    set(gcf, 'Position',  [100, 100, 800, 1600]);
    
    % For every ROI
    for i = 1:length(labels)
        
        
        
        % Calculate mean and 95% confidence intervals for deviants
        [mean_deviant, CI_deviant] = mq_get_confidence_cousineau(squeeze(...
            VE_deviant_grandavg.individual(:,i,:)));
        
        % Calculate mean and 95% confidence intervals for standards
        [mean_standard, CI_standard] = mq_get_confidence_cousineau(squeeze(...
            VE_standard_grandavg.individual(:,i,:)));
        
  %%% ADDED top
        cfg                  = [];
        cfg.channel          = VE_deviant_all{1,1}.label{i};
        cfg.latency          = [0 0.5];
        %cfg.dim             = VE_deviant_all{1,i}.dim;
        cfg.method           = 'montecarlo';
        cfg.statistic        = 'ft_statfun_depsamplesT';
        cfg.parameter        = 'avg';
        cfg.correctm         = 'cluster';
        cfg.computecritval   = 'yes';
        cfg.numrandomization = 2000;  % NB. Only did 1000 for the sensor level. More computationally difficult to do >1000 for sensor-lvl since more channels to process. Can do way more for source.
        %cfg.clusteralpha    = 0.001;
        cfg.tail             = 0;    % Two sided testing
        cfg.alpha            = 0.05;
        % Design Matrix
        nsubj           = length(VE_deviant_all);
        cfg.design(1,:) = [1:nsubj 1:nsubj];
        cfg.design(2,:) = [ones(1,nsubj) ones(1,nsubj)*2];
        cfg.uvar        = 1; % row of design matrix that contains unit variable (in this case: subjects)
        cfg.ivar        = 2; % row of design matrix that contains independent variable (the conditions)
        %
        stat            = ft_timelockstatistics(cfg,VE_deviant_all{:},...
            VE_standard_all{:});
        mask_param                = double(stat.mask);
        mask_param(mask_param==0) = NaN;
        %         mask_param(mask_param==1) = -1.4e-13;
        mask_param(mask_param==1) = -.9e-13;
        mask_param_all(i,:) = mask_param;   
   %%% ADDED bottom

        
        % Plot using boundedline
        %         subplot(3,2,i);plot(x,mean_standard,x,mean_deviant);
        % OR
        %     % Plot using boundedline (CIS
        subplot(3,2,i);boundedline(x,mean_deviant,CI_deviant(2,:),...
            x,mean_standard,...
            CI_standard(2,:),'alpha','transparency',0.3,'cmap',cmap);
        
        
        % Label and adjust lims
        xlabel('Time (sec)');
        ylabel('Amplitude (Tesla/cm^{2})')
        %ylim([-4.2e-13 3.5e-13]);
        %ylim([-2.3e-13 2.3e-13]);
        
                %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %%%%%%%%%%%%%%% Y LIMITS FOR EACH ROI %%%%%%%%%%%%%%%%%%%%
        %         ylim([-10e-5 5e-5]);
        limits = {([-13e-6 12e-6]),([-13e-6 12e-6]),([-4e-5 3e-5]),([-4e-5 3e-5]),([-1.5e-4 1.5e-4]),([-1.5e-4 1.5e-4])};
        ylim(limits{i});
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        
        
        xlim([0 0.51]);
        
        % Adjust FontSize
        set(gca,'fontsize', 14);
    %%% ADDED below       
      hold on; drawnow;
        plot([0:.001:0.5],mask_param,'-k','LineWidth',3);
        ax = gca;
%         ax.YRuler.TickLabelFormat = '%.0f';
    %%% ADDED above
    
        % Give the subplot a title (ROI)
        title(sprintf('%s',labels{i}),'Interpreter', 'none','FontSize',18);
        
    end
    
    
    print(['/Users/42450500/OneDrive - Macquarie University/phd/data/MEG/ME175/inUse/group/png/', group_list{q},'_VE_SvD'],'-dpng','-r300');
    
    
    
    
    close all
    % clear mean_deviant mean_standard
    cd(orig);
    
    
end % end age group loop


%% young vs old statistica comparison

load('/Users/42450500/OneDrive - Macquarie University/phd/data/MEG/ME175/inUse/group/variables/MMF_all_older.mat')
old_mmf = MMF_all;

load('/Users/42450500/OneDrive - Macquarie University/phd/data/MEG/ME175/inUse/group/variables/MMF_all_younger.mat')
young_mmf = MMF_all;

for i = 1:length(labels)
    
    cfg                  = [];
    %     cfg.channel          = MMF_all{1,1}.label{i};
    cfg.channel          = VE_deviant_all{1,1}.label{i};
    cfg.latency          = [0 0.5];
    %cfg.dim             = VE_deviant_all{1,i}.dim;
    cfg.method           = 'montecarlo';
    cfg.statistic        = 'ft_statfun_indepsamplesT';
    cfg.parameter        = 'individual';
    cfg.correctm         = 'cluster';
    cfg.computecritval   = 'yes';
    cfg.numrandomization = 2000;  % NB. Only did 1000 for the sensor level. More computationally difficult to do >1000 for sensor-lvl since more channels to process. Can do way more for source.
    %cfg.clusteralpha    = 0.001;
    cfg.tail             = 0;    % Two sided testing
    cfg.alpha            = 0.05;
    
    
    % Design Matrix
    design = [ones(1,length(group.older)) 2*ones(1,length(group.younger))];
    cfg.design      = design;
    cfg.ivar        = 1; % row of design matrix that contains independent variable (the conditions)
    %%% EXPLANATION: 'ones' is used to create a matrix. e.g.1., 'ones(4)' creates
    %%% a 4x4 matrix of 1s. e.g.2., 'ones(1,4)' creates one row of four 1s. For
    %%% b/w-subjects, comparing a row of group A/old (1s) with group B/young (2s).
    %%% To create the 2s = 2*ones = 2s. Call this 'deisgn' into the cfg settings.
    %%% the ivar is 'group' (with two levels, young vs old
    
    
    stat_MMFbyGrpROI.(labels{i})            = ft_timelockstatistics(cfg,old_mmf,young_mmf);
    
end
save (['/Users/42450500/OneDrive - Macquarie University/phd/data/MEG/ME175/inUse/group/variables/','stat_MMFbyGrpROI.(labels{i}'], 'stat_MMFbyGrpROI');

stat_MMFbyGrpROI.Left_A1.mask % etc. (x6 ROI) to check for sig. young v old MMF differences

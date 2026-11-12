% =========================================================================
% FYSKA MASTER CONFIGURATION SCRIPT
% =========================================================================
clear; clc; close all;

%% 1. RAW DATA LOCATION & CHANNELS
cfg.raw_data_path           = 'C:\Research\Data\cut7-GFP sid4-mCh\MB1302\Segmented Cells';
cfg.cell_type               = '1302_200Rq2_100G_9Z_25deg';
cfg.cell_id                 = '000_X';
cfg.file_ext                = '.mat';

% --- DYNAMICALLY CONSTRUCTED PATHS & IDENTIFIERS ---
cfg.data_name               = cfg.cell_id;
cfg.file_prefix             = [cfg.cell_type, '_', cfg.cell_id];
cfg.full_input_path         = char(fullfile(cfg.raw_data_path, [cfg.file_prefix, cfg.file_ext]));

% Anchor root path to config directory
proj_root                   = fileparts(mfilename('fullpath'));
cfg.out_data_path           = char(fullfile(proj_root, 'saved data', cfg.cell_type, cfg.cell_id));

% --- CHANNEL SETTINGS ---
cfg.num_channels            = 2;
cfg.channel_names           = {'sid4', 'cut7'};

% Frame sampling interval per channel
cfg.frame_sampling_interval = [2, 1]; 

%% 2. PHYSICAL CALIBRATION & KYMOGRAPH EXTENSION
cfg.micron_per_pix          = []; % e.g., 0.1067
cfg.time_step               = []; % e.g., 8.89609 (seconds)
cfg.ROI_end_extension_length = 10; % Line extension length beyond spots (in pixels)

%% 3. PIPELINE CONTROL FLAGS
cfg.reuse_saved_spot_pos    = 1;  % 1 = bypass tracking and load pos_spots_final.mat directly; 0 = re-track
cfg.movie_on                = 0;  % GLOBAL SWITCH: 1 = render movies, 0 = bypass all movie calls completely

%% 4. TRACKING & REFINEMENT OPTIONS
cfg.AutoFindSPB             = 1;      % 1 = auto detection, 0 = manual click tagging
cfg.spb_find_thresh         = 2;      % Number of stds above background for spot finding
cfg.refine_spots            = 1;      % 1 = refine spot positions via 2D Gaussian fitting, 0 = no refinement
cfg.refine_protrusion       = 'all';  % 'all', [], or frame array e.g., [2, 17, 21:27]
cfg.gauss_fit_radius        = 4;      % Sub-pixel Gaussian 2D fitting window radius (pixels)
cfg.gauss_max_shift         = 3;      % Maximum pixel shift of the refined pos relative to raw
cfg.autocorrect_thresh      = 5;      % Auto-correction outlier distance threshold (pixels)
cfg.frames_per_click        = 2;      % Number of frames to skip per click during manual tagging
cfg.first_frame             = [];     % [] prompts user input if tracking from scratch
cfg.last_frame              = [];     % [] prompts user input if tracking from scratch
cfg.prot_first_frame        = [];     % [] prompts user input for protrusion start frame
cfg.prot_last_frame         = [];     % [] prompts user input for protrusion end frame

%% 5. FIGURE & PLOT STYLING PARAMETERS
cfg.plot.fig_units          = 'centimeters';
cfg.plot.fig_pos            = [5, 5, 16, 12];
cfg.plot.font_name          = 'Arial';
cfg.plot.font_size          = 28;
cfg.plot.label_size         = 30;
cfg.plot.font_weight        = 'normal';     % Global font weight: 'normal' or 'bold'
cfg.plot.line_width         = 2;
cfg.plot.x_tick_step        = 5;        % X-axis tick spacing (minutes); [] = MATLAB automatic ticks
cfg.plot.y_tick_step        = [];        % Y-axis tick spacing (degrees or um); [] = MATLAB automatic ticks

% --- KINEMATICS PLOT LINE COLORS ---
cfg.plot.c_spindle          = [0.6, 0.0, 0.0]; % Dark red
cfg.plot.c_protrusion       = [1.0, 0.3, 0.7]; % Pinkish red
cfg.plot.c_angle            = [0.9, 0.7, 0.2]; % Gold

% --- STANDALONE DIAGNOSTIC MOVIE & SNAPSHOT PARAMETERS ---
cfg.plot.movie.channels         = [1, 2];         % 1 = Red only, 2 = Green only, [1, 2] = Merged RGB
cfg.plot.colormap               = 'gray';         % 'gray', 'red', 'green', 'blue' (ignored for merged [1, 2])
cfg.plot.movie.box_size         = 0;              % 0 = hide boxes; >0 = box half-width (pixels) around spots
cfg.plot.movie.box_colors = { ... % use [] to hide particular box
                              [0.9, 0.0, 0.0], ... % Line 1: Far SPB (SPB1, red)
                              [1.0, 0.9, 0.0], ... % Line 2: Mid-spindle center, yellow
                              [0.5, 0.9, 0.0], ... % Line 3: SPB2 (Spindle alignment - sour green)
                              [0.2, 0.8, 0.4], ... % Line 4: SPB2 (Protrusion alignment - aqua green)
                              [0.2, 0.4, 0.8], ... % Line 5: Mid-protrusion center, cyan
                              [0.0, 0.1, 0.9]  ... % Line 6: Protrusion tip, blue
                            };
cfg.plot.movie.spot_marker      = 'o';            % 'o', 'x', '+', or 'none' / '' to hide spot markers
cfg.plot.movie.spot_size        = 10;             % Set to 0 to hide spot markers
cfg.plot.movie.loi_spb_color    = [1, 1, 0];      % LOI SPB segment - Yellow
cfg.plot.movie.loi_prot_color   = [0, 1, 1];      % LOI Protrusion segment - Cyan
cfg.plot.movie.colorbar         = false;          % Show intensity colorbar on the right
cfg.plot.movie.display_fps      = 50;             % Interactive playback speed (FPS)
cfg.plot.movie.replay_fps       = 10;             % Saved video frame rate (FPS)
cfg.plot.movie.file_format      = '.avi';         % '.avi' or '.mp4'
cfg.plot.movie.output_name      = '';             % Default: empty -> uses data_name + '_movie'
cfg.plot.movie.snapshots        = [];             % Frame numbers to export high-res PNG publication snapshots (set [] to disable)
cfg.plot.movie.show_title       = true;           % Display Cell ID, Channel, Frame
cfg.plot.movie.show_axis_ticks  = true;           % Show tick marks/numbers on axes
cfg.plot.movie.show_axis_labels = true;           % Show axis labels (e.g. Distance / Pixels)
cfg.plot.movie.axis_unit        = 'pixels';       % 'micron' or 'pixels'
cfg.plot.movie.x_tick_step      = 20;             % X-axis tick spacing; [] = MATLAB automatic ticks
cfg.plot.movie.y_tick_step      = 20;             % Y-axis tick spacing; [] = MATLAB automatic ticks
cfg.plot.movie.fig_pos          = [100, 100, 800, 600]; % On-screen window size [x, y, width, height]

% --- CONTRAST CONFIGURATION ---
cfg.plot.movie_contrast.red   = [200, 400];  
cfg.plot.movie_contrast.green = [200, 450];  
cfg.plot.kymo_contrast.red    = cfg.plot.movie_contrast.red;
cfg.plot.kymo_contrast.green  = cfg.plot.movie_contrast.green;

% --- KYMOGRAPH AXIS & LABEL CONTROL ---
cfg.plot.kymo.show_axis   = true;       % true = show axis frame & numbers; false = hide frame completely
cfg.plot.kymo.x_unit      = 'um';       % Spatial unit: 'pixel' or 'um'
cfg.plot.kymo.t_unit      = 'min';      % Temporal unit: 'frame', 's', or 'min'
cfg.plot.kymo.x_label     = ' ';     % 'auto' = auto-generate; '' = hide text label (numbers only); 'custom' = custom text
cfg.plot.kymo.t_label     = ' ';     % 'auto' = auto-generate; '' = hide text label (numbers only); 'custom' = custom text
cfg.plot.kymo.font_size   = 14;         % Tick number font size (leave [] to use cfg.plot.font_size)
cfg.plot.kymo.label_size  = 14;         % Axis title font size (leave [] to use cfg.plot.label_size)
cfg.plot.kymo.font_weight = 'normal';     % Kymograph font weight: 'normal', 'bold', or [] (leave [] to use cfg.plot.font_weight)
cfg.plot.kymo.x_tick_step  = 2;         % X-axis tick spacing in selected x_unit; [] = MATLAB automatic ticks
cfg.plot.kymo.y_tick_step  = 5;         % Y-axis tick spacing in selected t_unit; [] = MATLAB automatic ticks

%% 6. SAVE CONFIGURATION (.MAT AND .TXT)
if ~exist(cfg.out_data_path, 'dir'), mkdir(cfg.out_data_path); end

% Save MATLAB structure
save(fullfile(cfg.out_data_path, 'config_params.mat'), 'cfg');

% Save Human-Readable Text Summary
saveStructToTxt(cfg, fullfile(cfg.out_data_path, 'config_params.txt'));
fprintf('Configuration saved to:\n - %s\n - %s\n', ...
        fullfile(cfg.out_data_path, 'config_params.mat'), ...
        fullfile(cfg.out_data_path, 'config_params.txt'));

%% LOCAL HELPER FOR TEXT EXPORT
function saveStructToTxt(S, txt_path)
    fid = fopen(txt_path, 'w');
    if fid == -1, return; end
    
    fprintf(fid, "=========================================================\n");
    fprintf(fid, " FYSKA CONFIGURATION PARAMETERS SUMMARY\n");
    fprintf(fid, " Generated on: %s\n", datestr(now, 'yyyy-mm-dd HH:MM:SS'));
    fprintf(fid, "=========================================================\n\n");
    
    printFieldsRecursive(fid, S, '');
    fclose(fid);
end

function printFieldsRecursive(fid, S, prefix)
    fnames = fieldnames(S);
    for i = 1:length(fnames)
        fn = fnames{i};
        val = S.(fn);
        
        if isempty(prefix)
            key_str = fn;
        else
            key_str = [prefix, '.', fn];
        end
        
        if isstruct(val)
            fprintf(fid, "\n[%s]\n", key_str);
            printFieldsRecursive(fid, val, key_str);
        elseif isempty(val)
            fprintf(fid, "%-35s = []\n", key_str);
        elseif isnumeric(val) || islogical(val)
            if isscalar(val)
                fprintf(fid, "%-35s = %g\n", key_str, val);
            else
                fprintf(fid, "%-35s = %s\n", key_str, mat2str(val));
            end
        elseif ischar(val) || isstring(val)
            fprintf(fid, "%-35s = '%s'\n", key_str, char(val));
        elseif iscell(val)
            cell_str = strjoin(cellfun(@mat2str, val, 'UniformOutput', false), ', ');
            fprintf(fid, "%-35s = {%s}\n", key_str, cell_str);
        end
    end
end
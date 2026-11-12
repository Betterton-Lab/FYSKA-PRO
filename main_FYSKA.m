clear; clc; close all;

% Add functions directory and subfolders to MATLAB path
addpath(genpath(pwd)); 

% 1. Load Master Configuration
config_FYSKA; 

% 2. Load Stacks & Auto-Detect Calibration Metadata
[movies3D, cfg] = loadAndPrepareData(cfg);

% 3. Track or Load Coordinates
[pos_spots_final, pos_spots_raw, pos_spots_manual] = trackAndRefineSpots(movies3D, cfg);

% --- GENERATE KINEMATICS PLOTS ---
plotSPDynamics(pos_spots_final, cfg);

% % 4. Render Movie 1: Spot-Only Diagnostic (LineWidth = 0)
showDiagnosticMovie(movies3D, pos_spots_final, cfg, ...
                    'line_width', 0, ...
                    'box_size', 0, ...
                    'output_name', [cfg.data_name, '_spots_only']);

% % 5. Render Movie 2: Kymograph Interpolation Alignment Check (LineWidth = 1.5, LOI extension shown)
showDiagnosticMovie(movies3D, pos_spots_final, cfg, ...
                    'channels', [1,2], ...
                    'line_width', 1.5, ...
                    'box_size', 0, ...
                    'output_name', [cfg.data_name, '_loi_verification']);

% % 6. Render Movie 3: Regional Intensity Boxes
showDiagnosticMovie(movies3D, pos_spots_final, cfg, ...
                    'channels', 2, ...
                    'spot_marker', 'none', ...
                    'line_width', 0, ...
                    'box_size', 4, ...
                    'output_name', [cfg.data_name, '_regional_boxes']);

% 7. Generate & Export Single-Channel Kymographs
kymo_raw = cell(1, cfg.num_channels);
kymo_opt = cell(1, cfg.num_channels);

% for c = 1:cfg.num_channels
%     [kymo_raw{c}, kymo_opt{c}, x_ax, t_ax] = makeAdvancedKymograph(movies3D{c}, pos_spots_final, c, cfg);
% end

% Show kymograph creation demo: 
for c = 1:cfg.num_channels
    [kymo_raw{c}, kymo_opt{c}, x_ax, t_ax] = makeKymographDemo(movies3D, pos_spots_final, c, cfg);
end

% 8. Export Merged Multi-Channel Kymograph
if cfg.num_channels >= 2
    exportMergedKymograph(kymo_opt{1}, kymo_opt{2}, x_ax, t_ax, cfg);
end

disp('FYSKA pipeline completed successfully!');

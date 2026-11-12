function [movies3D, cfg] = loadAndPrepareData(cfg)
    % LOADANDPREPAREDATA Reads image stack (.mat or .tif), auto-extracts metadata,
    % handles fallback units, and corrects uneven frame sampling.

    input_path = char(cfg.full_input_path);
    if ~exist(input_path, 'file')
        error('LoadAndPrepareData:FileNotFound', 'File not found:\n%s', input_path);
    end

    [~, file_name, ext] = fileparts(input_path);
    fprintf('Loading raw data stack: %s\n', input_path);

    % --- 1. DATA EXTRACTION ---
    if strcmpi(ext, '.tif') || strcmpi(ext, '.tiff')
        % Cache directory and MAT output path
        if ~exist(cfg.out_data_path, 'dir')
            mkdir(cfg.out_data_path);
        end
        mat_cache_path = fullfile(cfg.out_data_path, [file_name, '.mat']);

        if exist(mat_cache_path, 'file')
            fprintf('Found existing converted MAT file. Loading from:\n%s\n', mat_cache_path);
            loaded_data = load(mat_cache_path, 'ImageData');
            ImageData   = loaded_data.ImageData;
        else
            fprintf('Reading TIF volume into memory...\n');
            ImageData = tiffreadVolume(input_path);
            
            fprintf('Saving converted MAT file to:\n%s\n', mat_cache_path);
            save(mat_cache_path, 'ImageData', '-v7.3');
        end

        % Reshape interleaved ImageData [H, W, TotalSlices] into 5D stack [H, W, Z=1, T, C]
        [h, w, total_slices] = size(ImageData);
        num_ch = cfg.num_channels;
        total_frames = floor(total_slices / num_ch);

        movie5D = zeros(h, w, 1, total_frames, num_ch);
        for c = 1:num_ch
            movie5D(:, :, 1, :, c) = ImageData(:, :, c:num_ch:(total_frames * num_ch));
        end

    elseif strcmpi(ext, '.mat')
        mat_contents = load(input_path);
        
        if isfield(mat_contents, 'cellData')
            raw_cell = mat_contents.cellData;
            movie5D  = raw_cell.cell3D; % (X, Y, Z, T, C)
            
            % Auto-extract pixel size if not specified in config
            if isempty(cfg.micron_per_pix) && isfield(raw_cell, 'metaData') && isfield(raw_cell.metaData, 'sizeVoxelsX')
                cfg.micron_per_pix = double(raw_cell.metaData.sizeVoxelsX);
            end
            
            % Auto-extract frame time interval if not specified in config
            if isempty(cfg.time_step) && isfield(raw_cell, 'planeTimes')
                planeTimes = double(raw_cell.planeTimes);
                planeTimes(planeTimes == 0) = NaN; % Missing/unused plane timestamps

                timesTC = squeeze(mean(planeTimes, 1, 'omitnan'));
                dt_steps = diff(timesTC, 1, 1);

                if ~isempty(dt_steps)
                    cfg.time_step = mean(dt_steps, 'all', 'omitnan');
                end
            end
        elseif isfield(mat_contents, 'image')
            movie5D = mat_contents.image;
        elseif isfield(mat_contents, 'ImageData')
            ImageData = mat_contents.ImageData;
            [h, w, total_slices] = size(ImageData);
            num_ch = cfg.num_channels;
            total_frames = floor(total_slices / num_ch);

            movie5D = zeros(h, w, 1, total_frames, num_ch);
            for c = 1:num_ch
                movie5D(:, :, 1, :, c) = ImageData(:, :, c:num_ch:(total_frames * num_ch));
            end
        else
            error('LoadAndPrepareData:InvalidFormat', 'Unrecognized dataset structure in .mat file.');
        end
    else
        error('LoadAndPrepareData:UnsupportedExtension', 'Unsupported file format: %s', ext);
    end

    % --- 2. METADATA VALIDATION & FALLBACK ---
    if isempty(cfg.micron_per_pix) || isempty(cfg.time_step)
        warning('Metadata not found or not specified. Defaulting to frame and pixel units.');
        cfg.use_physical_units = false;
        cfg.micron_per_pix     = 1.0;
        cfg.time_step          = 1.0;
        cfg.unit_x_label       = 'Distance (pixels)';
        cfg.unit_t_label       = 'Time (frames)';
    else
        cfg.use_physical_units = true;
        cfg.unit_x_label       = 'Distance (\mum)';
        cfg.unit_t_label       = 'Time (Minutes)';
        fprintf('Image Info Found!  Pixel = %.4f µm, Frame Time = %.2f sec\n', ...
            cfg.micron_per_pix, cfg.time_step);
    end

    % --- 2B. SAVE RESOLVED CALIBRATION FOR THIS CELL ---
    % The config script saves config_params before automatic metadata
    % extraction, so persist the resolved values here as well.
    if ~exist(cfg.out_data_path, 'dir')
        mkdir(cfg.out_data_path);
    end

    calibration_info = struct();
    calibration_info.input_file = input_path;
    calibration_info.use_physical_units = cfg.use_physical_units;
    calibration_info.time_step = cfg.time_step;               % seconds/frame (1 if fallback)
    calibration_info.micron_per_pix = cfg.micron_per_pix;     % um/pixel (1 if fallback)
    calibration_info.pixels_per_micron = NaN;                 % unknown if fallback
    if cfg.use_physical_units
        calibration_info.pixels_per_micron = 1 / cfg.micron_per_pix;
    end

    save(fullfile(cfg.out_data_path, 'calibration_info.mat'), 'calibration_info');
    % Refresh the saved MATLAB config too, now that metadata is resolved.
    save(fullfile(cfg.out_data_path, 'config_params.mat'), 'cfg');

    calibration_txt = fullfile(cfg.out_data_path, 'calibration_info.txt');
    fid = fopen(calibration_txt, 'w');
    if fid == -1
        warning('LoadAndPrepareData:CalibrationTxt', ...
            'Could not write calibration text file: %s', calibration_txt);
    else
        fprintf(fid, 'FYSKA CALIBRATION INFORMATION\n');
        fprintf(fid, 'Input file: %s\n\n', input_path);
        if cfg.use_physical_units
            fprintf(fid, 'Time step          = %.10g seconds/frame\n', cfg.time_step);
            fprintf(fid, 'Micron per pixel   = %.10g um/pixel\n', cfg.micron_per_pix);
            fprintf(fid, 'Pixels per micron  = %.10g pixels/um\n', calibration_info.pixels_per_micron);
        else
            fprintf(fid, 'PHYSICAL CALIBRATION NOT AVAILABLE.\n');
            fprintf(fid, 'The loader uses 1 for time_step and micron_per_pix\n');
            fprintf(fid, 'as fallback values (frames and pixels, NOT seconds or um).\n');
        end
        fclose(fid);
        fprintf('Calibration saved to: %s\n', calibration_txt);
    end

    % --- 3. CHANNEL SPLITTING & FRAME SAMPLING CORRECTION ---
    movies3D = cell(1, cfg.num_channels);
    for c = 1:cfg.num_channels
        ch_movie = double(squeeze(movie5D(:,:,:,:,c)));
        interval = cfg.frame_sampling_interval(c);

        % If imaged every N frames, duplicate filled odd frames into missing gaps
        if interval > 1
            fprintf('Applying %dX frame duplication to Channel %d...\n', interval, c);
            for s = 2:interval
                if ndims(ch_movie) == 4
                    ch_movie(:,:,:, s:interval:end) = ch_movie(:,:,:, 1:interval:end-interval+1);
                else
                    ch_movie(:,:, s:interval:end)   = ch_movie(:,:, 1:interval:end-interval+1);
                end
            end
        end
        movies3D{c} = ch_movie;
    end

    disp('Data stack successfully loaded and prepared.');
end
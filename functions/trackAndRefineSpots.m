function [pos_spots_final, pos_spots_raw, pos_spots_manual] = trackAndRefineSpots(movies3D, cfg)
    % TRACKANDREFINESPOTS Tracks and refines spot positions.
    % Movie generation is completely decoupled from this function.

    target_spots_file = fullfile(cfg.out_data_path, 'pos_spots_final.mat');

    %% 1. REUSE PRE-EXISTING TRACKING DATA
    if isfield(cfg, 'reuse_saved_spot_pos') && cfg.reuse_saved_spot_pos == 1
        if exist(target_spots_file, 'file')
            fprintf('Loading existing tracking coordinates from:\n%s\n', target_spots_file);
            loaded_data = load(target_spots_file);
            
            if isfield(loaded_data, 'pos_spots_final')
                pos_spots_final  = ensureThreeSpotRows(loaded_data.pos_spots_final);
                pos_spots_raw    = ensureThreeSpotRows(getLoadedField(loaded_data, 'pos_spots_raw', pos_spots_final));
                pos_spots_manual = ensureThreeSpotRows(getLoadedField(loaded_data, 'pos_spots_manual', pos_spots_final));

                spb_valid  = find(~isnan(squeeze(pos_spots_final(1,1,:))) & ...
                                  ~isnan(squeeze(pos_spots_final(2,1,:))));
                prot_valid = find(~isnan(squeeze(pos_spots_final(3,1,:))));

                if isempty(spb_valid)
                    spb_start = []; spb_end = [];
                else
                    spb_start = spb_valid(1); spb_end = spb_valid(end);
                end
                if isempty(prot_valid)
                    prot_start = []; prot_end = [];
                else
                    prot_start = prot_valid(1); prot_end = prot_valid(end);
                end

                fprintf('Active Frame Boundaries: SPB [%s - %s] | Protrusion [%s - %s]\n', ...
                        fmtVal(spb_start), fmtVal(spb_end), fmtVal(prot_start), fmtVal(prot_end));
                if isempty(prot_valid)
                    disp('No protrusion track found. Continuing in 2-spot mode.');
                end
                disp('Pre-existing tracking data loaded successfully.');
                
                % Export frame info txt file for pre-existing tracking runs
                exportFrameInfoTxt(pos_spots_final, cfg);
                return;
            end
        end
    end

    %% 2. INITIALIZE DATA & DETERMINE FRAME BOUNDS
    disp('Initiating spot selection/tracking workflow from scratch...');
    
    if ndims(movies3D{1}) == 4
        Ch1 = squeeze(max(movies3D{1}, [], 3));
        Ch2 = squeeze(max(movies3D{2}, [], 3));
    else
        Ch1 = movies3D{1};
        Ch2 = movies3D{2};
    end

    total_frames = size(Ch1, 3);
    
    if isfield(cfg, 'first_frame') && ~isempty(cfg.first_frame)
        first_frame = cfg.first_frame;
    else
        user_start = input(sprintf('Enter start frame (1 to %d) [Press ENTER for default 1]: ', total_frames));
        first_frame = ternary(isempty(user_start), 1, user_start);
    end

    if isfield(cfg, 'last_frame') && ~isempty(cfg.last_frame)
        last_frame = cfg.last_frame;
    else
        user_end = input(sprintf('Enter end frame (%d to %d) [Press ENTER for default %d]: ', first_frame, total_frames, total_frames));
        last_frame = ternary(isempty(user_end), total_frames, user_end);
    end

    frames_step      = getCfgField(cfg, 'frames_per_click', 1);
    pos_spots_final  = NaN(3, 2, total_frames);
    pos_spots_raw    = NaN(3, 2, total_frames);
    pos_spots_manual = NaN(3, 2, total_frames);

    [c_red, c_green] = parseContrastLimits(cfg);

    % Color definitions for SPBs during tagging (both mostly red, distinct shades)
    c_spb1_red  = [1.0, 0.1, 0.3]; % Crimson Red for SPB 1
    c_spb2_red  = [0.9, 0.4, 0.1]; % Vermilion Red for SPB 2
    c_dark_gray = [0.2, 0.2, 0.2]; 

    %% 3. STEP 1: SPB TRACKING (AUTO OR MANUAL)
    auto_spb = getCfgField(cfg, 'AutoFindSPB', 1);
    spb_raw  = NaN(2, 2, total_frames);
    
    if auto_spb
        disp('--- Step 1: Auto-tracking SPBs in Channel 1 ---');
        spb_thresh = getCfgField(cfg, 'spb_find_thresh', 2);
        spb_cand   = FindSpotsInMovie(Ch1, first_frame, last_frame, spb_thresh, 3);
        spb_raw    = KeepBrightestSpots(Ch1, spb_cand, 2);
    else
        disp('--- Step 1: Manual Tagging SPBs on Merged Channels ---');
        
        % Manual Tagging - SPB 1 (Merged View)
        fig_spb1 = figure('Name', 'Manual Tagging - SPB 1', 'WindowState', 'maximized');
        for f = first_frame : frames_step : last_frame
            r_img = AdjustContrastSmart(Ch1(:,:,f), c_red);
            g_img = AdjustContrastSmart(Ch2(:,:,f), c_green);
            rgb_img = cat(3, r_img, g_img, zeros(size(r_img)));
            
            imshow(rgb_img, 'InitialMagnification', 'fit'); hold on;
            title(sprintf('%s | Frame %d | Click SPB 1 (ENTER to Skip)', cfg.data_name, f), 'Interpreter', 'none');
            [x, y, ~] = ginput(1);
            if ~isempty(x)
                pos_spots_manual(1, :, f) = [x, y]; 
                spb_raw(1, :, f)          = [x, y];
                plot(x, y, 'o', 'Color', c_spb1_red, 'LineWidth', 2, 'MarkerSize', 17); pause(0.15);
            end
            hold off;
        end
        close(fig_spb1);

        % Manual Tagging - SPB 2 (Merged View)
        fig_spb2 = figure('Name', 'Manual Tagging - SPB 2', 'WindowState', 'maximized');
        for f = first_frame : frames_step : last_frame
            r_img = AdjustContrastSmart(Ch1(:,:,f), c_red);
            g_img = AdjustContrastSmart(Ch2(:,:,f), c_green);
            rgb_img = cat(3, r_img, g_img, zeros(size(r_img)));
            
            imshow(rgb_img, 'InitialMagnification', 'fit'); hold on;
            if ~isnan(spb_raw(1, 1, f))
                plot(spb_raw(1, 1, f), spb_raw(1, 2, f), 'o', 'Color', c_spb1_red, 'LineWidth', 2, 'MarkerSize', 17);
            end
            title(sprintf('%s | Frame %d | Click SPB 2 (ENTER to Skip)', cfg.data_name, f), 'Interpreter', 'none');
            [x, y, ~] = ginput(1);
            if ~isempty(x)
                pos_spots_manual(2, :, f) = [x, y]; 
                spb_raw(2, :, f)          = [x, y];
                plot(x, y, 'o', 'Color', c_spb2_red, 'LineWidth', 2, 'MarkerSize', 17); pause(0.15);
            end
            hold off;
        end
        close(fig_spb2);

        for s = 1:2
            spb_raw(s, 1, first_frame:last_frame) = fillmissing(squeeze(spb_raw(s, 1, first_frame:last_frame)), 'linear');
            spb_raw(s, 2, first_frame:last_frame) = fillmissing(squeeze(spb_raw(s, 2, first_frame:last_frame)), 'linear');
        end
    end
    
    img_h = size(Ch1, 1); img_w = size(Ch1, 2);
    if img_h == img_w
        user_sort = input('Image is square (img_h == img_w). Sort spots along which axis? (x/y) [default: x]: ', 's');
        if strcmpi(strtrim(user_sort), 'y')
            sort_param = 'y';
        else
            sort_param = 'x';
        end
    else
        sort_param = ternary(img_h > img_w, 'y', 'x');
    end

    spb_raw = Sort2Spots(spb_raw, sort_param);
    pos_spots_raw(1:2, :, :) = spb_raw;
    
    if getCfgField(cfg, 'refine_spots', 1) == 1
        disp('Refining SPB sub-pixel positions via 2D Gaussian fitting...');
        spb_fit = Fit2DGaussMovie(Ch1, spb_raw, first_frame, last_frame, cfg);
        spb_fit = Sort2Spots(spb_fit, sort_param);
    else
        spb_fit = spb_raw;
    end
    
    % Display and save auto-correction plot for all fresh tracking runs
    thresh_val = getCfgField(cfg, 'autocorrect_thresh', 5);
    spb_fit = AutoCorrectAndPlot(spb_fit, first_frame, last_frame, thresh_val, cfg, sort_param);

    %% 4. STEP 2: MANUAL PROTRUSION TAGGING
    disp('--- Step 2: Manual Protrusion Tagging ---');
    
    if isfield(cfg, 'prot_first_frame') && ~isempty(cfg.prot_first_frame)
        prot_first_frame = cfg.prot_first_frame;
    else
        user_p_start = input(sprintf('Enter protrusion start frame (%d to %d) [Press ENTER for default %d]: ', first_frame, last_frame, first_frame));
        prot_first_frame = ternary(isempty(user_p_start), first_frame, user_p_start);
    end

    if isfield(cfg, 'prot_last_frame') && ~isempty(cfg.prot_last_frame)
        prot_last_frame = cfg.prot_last_frame;
    else
        user_p_end = input(sprintf('Enter protrusion end frame (%d to %d) [Press ENTER for default %d]: ', prot_first_frame, last_frame, last_frame));
        prot_last_frame = ternary(isempty(user_p_end), last_frame, user_p_end);
    end

    fig_tag = figure('Name', 'Manual Protrusion Tagging', 'WindowState', 'maximized');
    
    for f = prot_first_frame : frames_step : prot_last_frame
        r_img = AdjustContrastSmart(Ch1(:,:,f), c_red);
        g_img = AdjustContrastSmart(Ch2(:,:,f), c_green);
        rgb_img = cat(3, r_img, g_img, zeros(size(r_img)));
        
        imshow(rgb_img, 'InitialMagnification', 'fit'); hold on;
        plot(spb_fit(1,1,f), spb_fit(1,2,f), 'o', 'Color', c_spb1_red, 'LineWidth', 2, 'MarkerSize', 17);
        plot(spb_fit(2,1,f), spb_fit(2,2,f), 'o', 'Color', c_spb2_red, 'LineWidth', 2, 'MarkerSize', 17);
        title(sprintf('%s | Frame %d | Click Protrusion Tip (ENTER to Skip)', cfg.data_name, f), 'Interpreter', 'none');
        
        [x, y, ~] = ginput(1);
        if ~isempty(x)
            pos_spots_manual(3, :, f) = [x, y];
            plot(x, y, '*', 'Color', c_dark_gray, 'MarkerSize', 20, 'LineWidth', 3); pause(0.15);
        end
        hold off;
    end
    close(fig_tag);

    prot_interp = squeeze(pos_spots_manual(3, :, :));
    if prot_last_frame >= prot_first_frame
        prot_interp(1, prot_first_frame:prot_last_frame) = fillmissing(squeeze(pos_spots_manual(3, 1, prot_first_frame:prot_last_frame)), 'linear');
        prot_interp(2, prot_first_frame:prot_last_frame) = fillmissing(squeeze(pos_spots_manual(3, 2, prot_first_frame:prot_last_frame)), 'linear');
    end
    pos_spots_raw(3, :, :) = reshape(prot_interp, [1, 2, total_frames]);

    %% 5. STEP 3: GAUSSIAN REFINEMENT & PROTRUSION SORTING
    disp('--- Step 3: Sub-pixel Gaussian Refinement on Protrusions ---');
    if getCfgField(cfg, 'refine_spots', 1) == 1
        refine_setting = getCfgField(cfg, 'refine_protrusion', 'all');
        if isequal(refine_setting, 1) || isequal(refine_setting, true) || strcmpi(string(refine_setting), "all")
            frames_to_refine = prot_first_frame : prot_last_frame;
        elseif isnumeric(refine_setting)
            frames_to_refine = refine_setting;
        else
            frames_to_refine = [];
        end
        
        if ~isempty(frames_to_refine)
            prot_fit_temp = Fit2DGaussMovie(Ch2, reshape(prot_interp, [1, 2, total_frames]), prot_first_frame, prot_last_frame, cfg);
            prot_refined  = reshape(prot_interp, [1, 2, total_frames]);
            valid_frames  = intersect(frames_to_refine, prot_first_frame:prot_last_frame);
            prot_refined(1, :, valid_frames) = prot_fit_temp(1, :, valid_frames);
        else
            prot_refined = reshape(prot_interp, [1, 2, total_frames]);
        end
    else
        prot_refined = reshape(prot_interp, [1, 2, total_frames]);
    end
    
    pos_spots_final(1:2, :, :) = spb_fit;
    pos_spots_final(3, :, :)   = prot_refined(1, :, :);
    pos_spots_final            = OrganizeByProtrusion(pos_spots_final, first_frame, last_frame);

    %% 6. SAVE TRACKING RESULTS
    if ~exist(cfg.out_data_path, 'dir'), mkdir(cfg.out_data_path); end
    save(target_spots_file, 'pos_spots_final', 'pos_spots_raw', 'pos_spots_manual');
    fprintf('All tracking coordinates (manual, raw, final) saved to:\n%s\n', target_spots_file);

    % Export frame info text file for fresh tracking runs
    exportFrameInfoTxt(pos_spots_final, cfg);
end

%% LOCAL HELPER FUNCTIONS
function exportFrameInfoTxt(pos_spots, cfg)
    pos_spots = ensureThreeSpotRows(pos_spots);
    out_dir = getCfgField(cfg, 'out_data_path', pwd);
    if ~exist(out_dir, 'dir'), mkdir(out_dir); end

    spb_valid  = find(~isnan(squeeze(pos_spots(1,1,:))) & ~isnan(squeeze(pos_spots(2,1,:))));
    prot_valid = find(~isnan(squeeze(pos_spots(3,1,:))));

    if isempty(spb_valid)
        f_start = []; f_end = [];
    else
        f_start = spb_valid(1); f_end = spb_valid(end);
    end

    if isempty(prot_valid)
        pf_start = []; pf_end = [];
    else
        pf_start = prot_valid(1); pf_end = prot_valid(end);
    end

    txt_path = fullfile(out_dir, 'frame_info.txt');
    fid = fopen(txt_path, 'w');
    if fid ~= -1
        fprintf(fid, "=========================================================\n");
        fprintf(fid, " FYSKA TRACKED FRAME BOUNDARIES SUMMARY\n");
        fprintf(fid, " Dataset Name : %s\n", char(getCfgField(cfg, 'data_name', 'N/A')));
        fprintf(fid, " Generated on : %s\n", datestr(now, 'yyyy-mm-dd HH:MM:SS'));
        fprintf(fid, "=========================================================\n\n");
        
        fprintf(fid, "SPB Active Range         : [%s - %s]\n", fmtVal(f_start), fmtVal(f_end));
        fprintf(fid, "Protrusion Active Range  : [%s - %s]\n\n", fmtVal(pf_start), fmtVal(pf_end));
        
        fprintf(fid, "first_frame       = %s\n", fmtVal(f_start));
        fprintf(fid, "last_frame        = %s\n", fmtVal(f_end));
        fprintf(fid, "prot_first_frame  = %s\n", fmtVal(pf_start));
        fprintf(fid, "prot_last_frame   = %s\n", fmtVal(pf_end));
        fclose(fid);
        
        fprintf('Tracked frame bounds exported to:\n%s\n', txt_path);
    end
end

function str = fmtVal(val)
    if isempty(val), str = '[]'; else, str = num2str(val); end
end

function val = getLoadedField(struct_in, field_name, default_val)
    if isfield(struct_in, field_name), val = struct_in.(field_name); else, val = default_val; end
end

function pos_spots = ensureThreeSpotRows(pos_spots)
    % Allow legacy/2-spot tracking files by padding missing spot 3 with NaNs.
    if size(pos_spots, 1) < 3
        pos_spots = cat(1, pos_spots, ...
            NaN(3 - size(pos_spots, 1), size(pos_spots, 2), size(pos_spots, 3)));
    end
end

function val = getCfgField(cfg, fieldname, default_val)
    if isfield(cfg, fieldname) && ~isempty(cfg.(fieldname)), val = cfg.(fieldname); else, val = default_val; end
end

function out = ternary(cond, true_val, false_val)
    if cond, out = true_val; else, out = false_val; end
end

function [c_red, c_green] = parseContrastLimits(cfg)
    if isfield(cfg, 'plot') && isfield(cfg.plot, 'movie_contrast')
        mc = cfg.plot.movie_contrast;
        if isstruct(mc), c_red = mc.red; c_green = mc.green;
        elseif ismatrix(mc) && all(size(mc) == [2, 2]), c_red = mc(1, :); c_green = mc(2, :);
        else, c_red = [200, 400]; c_green = [200, 450]; end
    else, c_red = [200, 400]; c_green = [200, 450]; end
end

function img_opt = AdjustContrastSmart(img, limits)
    img_double = double(img);
    if max(limits) <= 1
        img_opt = imadjust(rescale(img_double), limits, []);
    else
        raw_min = limits(1); raw_max = limits(2);
        img_opt = (img_double - raw_min) / (raw_max - raw_min);
        img_opt = max(0, min(1, img_opt));
    end
end

function pos_spots_ordered = Sort2Spots(pos_spots_rough, sort_by)
    if nargin < 2, sort_by = 'x'; end
    pos_spots_ordered = pos_spots_rough;
    for f = 1:size(pos_spots_rough, 3)
        x1 = pos_spots_rough(1,1,f); y1 = pos_spots_rough(1,2,f);
        x2 = pos_spots_rough(2,1,f); y2 = pos_spots_rough(2,2,f);
        if strcmpi(sort_by, 'x') && x2 < x1
            pos_spots_ordered(1,:,f) = pos_spots_rough(2,:,f);
            pos_spots_ordered(2,:,f) = pos_spots_rough(1,:,f);
        elseif strcmpi(sort_by, 'y') && y1 < y2
            pos_spots_ordered(1,:,f) = pos_spots_rough(2,:,f);
            pos_spots_ordered(2,:,f) = pos_spots_rough(1,:,f);
        end
    end
end

function pos_ordered = OrganizeByProtrusion(pos_spots, first_f, last_f)
    pos_ordered = pos_spots; swaps = 0; valid_frames = 0;
    for f = first_f:last_f
        if ~isnan(pos_spots(3,1,f)) && ~isnan(pos_spots(1,1,f)) && ~isnan(pos_spots(2,1,f))
            d13 = norm(squeeze(pos_spots(3,:,f) - pos_spots(1,:,f)));
            d23 = norm(squeeze(pos_spots(3,:,f) - pos_spots(2,:,f)));
            valid_frames = valid_frames + 1;
            if d13 < d23, swaps = swaps + 1; end
        end
    end
    if valid_frames > 0 && (swaps / valid_frames > 0.5)
        pos_ordered(1,:,:) = pos_spots(2,:,:); pos_ordered(2,:,:) = pos_spots(1,:,:);
    end
end

function pos_correct = AutoCorrectAndPlot(pos_raw, first_f, last_f, thres, cfg, sort_param)
    if nargin < 6, sort_param = 'x'; end
    pos_correct = pos_raw;
    sel = pos_raw(:,:,first_f:last_f);
    
    sel = Sort2Spots(sel, sort_param);
    pos_correct(:,:,first_f:last_f) = sel;
    
    axis_vec = squeeze(sel(1,:,:) - sel(2,:,:));
    dist_raw = sqrt(sum(axis_vec.^2, 1))';
    t = (first_f:last_f)';
    
    dist_fit = fillmissing(dist_raw, 'linear', 'EndValues', 'nearest');
    
    % Handle string formatting and output directory safely from cfg
    data_name_str = char(getCfgField(cfg, 'data_name', 'data'));
    clean_title   = strrep(data_name_str, '_', '-');
    
    if isfield(cfg, 'out_data_path') && ~isempty(cfg.out_data_path)
        out_dir = cfg.out_data_path;
    else
        out_dir = fullfile("saved data", data_name_str);
    end
    if ~exist(out_dir, 'dir'), mkdir(out_dir); end
    
    fit_func = fit(t, dist_fit, 'poly5', 'Normalize', 'on', 'Robust', 'Bisquare');
    fitted_vals = fit_func(t);
    bad_pts = find(abs(fitted_vals - dist_raw) > thres | isnan(dist_raw));
    
    % Extract figure position, units, and font sizes directly from Section 5 of cfg
    if isfield(cfg, 'plot')
        fig_units = getCfgField(cfg.plot, 'fig_units', 'centimeters');
        fig_pos   = getCfgField(cfg.plot, 'fig_pos', [5, 5, 16, 12]);
        f_font    = getCfgField(cfg.plot, 'font_size', 16);
        f_weight  = getCfgField(cfg.plot, 'font_weight', 'normal');
        line_w    = getCfgField(cfg.plot, 'line_width', 1.5);
    else
        fig_units = 'pixels';
        fig_pos   = [100, 100, 800, 600];
        f_font    = 14;
        f_weight  = 'normal';
        line_w    = 1.5;
    end
    
    fig_auto = figure('Name', 'SPB Auto-Correction Plot', 'Units', fig_units, 'Position', fig_pos);
    figure(fig_auto);
    drawnow;
    
    % Custom color palette plotting
    plot(t, dist_raw, '.-', 'Color', [0.8, 0, 0], 'LineWidth', line_w + 1, 'MarkerSize', 8, 'DisplayName', 'raw'); hold on;
    plot(t, fitted_vals, '.-', 'Color', [0.5, 0, 0.75], 'LineWidth', line_w, 'MarkerSize', 8, 'DisplayName', 'fitted');
    
    if ~isempty(bad_pts)
        plot(t(bad_pts), dist_raw(bad_pts), 'x', 'Color', [0.5, 0, 0], 'LineWidth', 3, 'MarkerSize', 15, 'DisplayName', 'filtered');
        
        sel(:,:,bad_pts) = NaN;
        
        pos_correct_sel = fillmissing(sel, 'linear', 3, 'SamplePoints', t, 'EndValues', 'nearest');
        pos_correct(:,:,first_f:last_f) = pos_correct_sel;
        
        corr_vec = squeeze(pos_correct_sel(1,:,:) - pos_correct_sel(2,:,:));
        corr_dist = sqrt(sum(corr_vec.^2, 1))';
        
        plot(t, corr_dist, '.-', 'Color', [0.85, 0.7, 0], 'LineWidth', line_w, 'MarkerSize', 8, 'DisplayName', 'correction');
    else
        plot(t, dist_raw, '.-', 'Color', [0, 0.8, 0.2], 'LineWidth', line_w, 'MarkerSize', 8, 'DisplayName', 'correction');
    end
    
    xlabel('Frames', 'FontSize', f_font, 'FontWeight', f_weight); 
    ylabel('Distance (pixels)', 'FontSize', f_font, 'FontWeight', f_weight);
    title(['Auto-Correction Results: ', clean_title], 'FontSize', f_font, 'FontWeight', f_weight, 'Interpreter', 'none'); 
    
    set(gca, 'FontSize', f_font, 'FontWeight', f_weight, 'LineWidth', 1.2);
    legend('Location', 'best', 'FontSize', f_font - 2);
    grid on;
    
    saveas(fig_auto, fullfile(out_dir, [data_name_str, '_autocorrection_plot.png']));
    pause(1.5); 
    close(fig_auto);
end

function pos_all_spots = FindSpotsInMovie(movie2D, first_f, last_f, thres, spot_size)
    total_frames = size(movie2D, 3); pos_all_spots = zeros(2, 2, total_frames);
    sp_radius = max(1, floor(spot_size / 2)); center_idx = ((2 * sp_radius + 1)^2 + 1) / 2;
    for f = first_f:last_f
        img = imgaussfilt3(movie2D(:,:,f)); img(img == 0) = NaN;
        med_val = median(img(:), 'omitnan');
        thresh = med_val + thres * std(img(:), 'omitnan');
        [img_row, img_col] = size(img); [c_rows, c_cols] = find(img > thresh);
        
        if ~isempty(c_rows)
            valid = (c_cols > spot_size) & (c_cols < (img_col - spot_size)) & ...
                    (c_rows > spot_size) & (c_rows < (img_row - spot_size));
            selected = [c_cols(valid), c_rows(valid)]; veto_id = [];
            for i = 1:size(selected, 1)
                roi = img((selected(i,2)-sp_radius):(selected(i,2)+sp_radius), ...
                          (selected(i,1)-sp_radius):(selected(i,1)+sp_radius));
                [~, max_idx] = max(roi, [], 'all');
                if max_idx ~= center_idx, veto_id = [veto_id, i]; end
            end
            selected(veto_id, :) = [];
            if ~isempty(selected), pos_all_spots(1:size(selected,1), :, f) = selected; end
        end
    end
    pos_all_spots(pos_all_spots == 0) = NaN;
end

function pos_spots_rough = KeepBrightestSpots(movie, all_spots, max_spots)
    box_radius = 3; total_frames = size(movie, 3); pos_spots_rough = zeros(max_spots, 2, total_frames);
    for f = 1:total_frames
        img = imgaussfilt3(movie(:,:,f));
        total_s = sum(~isnan(all_spots(:,1,f)));
        if total_s < 2
            pos_spots_rough(1,:,f) = all_spots(1,:,f);
        else
            sub_box = zeros(2*box_radius+1, 2*box_radius+1, total_s);
            for s = 1:total_s
                x_lo = max(1, all_spots(s,1,f) - box_radius);
                y_lo = max(1, all_spots(s,2,f) - box_radius);
                sub_box(:,:,s) = img(y_lo:y_lo+2*box_radius, x_lo:x_lo+2*box_radius);
            end
            sums = squeeze(sum(sum(sub_box, 'omitnan'), 'omitnan'));
            [~, sort_idx] = sort(sums, 'descend');
            for k = 1:min(max_spots, length(sort_idx))
                pos_spots_rough(k,:,f) = all_spots(sort_idx(k),:,f);
            end
        end
    end
    pos_spots_rough(pos_spots_rough == 0) = NaN;
end

function pos_fit = Fit2DGaussMovie(movie3D, pos_rough, first_f, last_f, cfg)
    total_frames = size(movie3D, 3); 
    num_spots    = size(pos_rough, 1);
    pos_fit      = NaN(num_spots, 2, total_frames); 
    
    r         = getCfgField(cfg, 'gauss_fit_radius', 4); 
    max_shift = getCfgField(cfg, 'gauss_max_shift', r - 1);
    
    gauss2D = @(p, c) p(5) + p(1) * exp(-((c(:,:,1)-p(2)).^2 + (c(:,:,2)-p(3)).^2)/(2*p(4)^2));
    opts    = optimoptions('lsqcurvefit', 'Display', 'off');
    
    for f = first_f:last_f
        img = imgaussfilt3(movie3D(:,:,f)); img(isnan(img)) = 0;
        for s = 1:num_spots
            rx = pos_rough(s, 1, f); ry = pos_rough(s, 2, f);
            if ~isnan(rx) && ~isnan(ry)
                x_lo = max(1, round(rx) - r); x_hi = min(size(img,2), round(rx) + r);
                y_lo = max(1, round(ry) - r); y_hi = min(size(img,1), round(ry) + r);
                sub  = double(img(y_lo:y_hi, x_lo:x_hi));
                if ~isempty(sub) && max(sub(:)) > 0
                    [X, Y] = meshgrid(1:size(sub,2), 1:size(sub,1));
                    x_seed = rx - x_lo + 1; y_seed = ry - y_lo + 1;
                    bg_guess  = median(sub(:)); amp_guess = max(0.1, max(sub(:)) - bg_guess);
                    guess = [amp_guess, x_seed, y_seed, 1.2, bg_guess];
                    lb    = [0, x_seed - max_shift, y_seed - max_shift, 0.5, 0];
                    ub    = [Inf, x_seed + max_shift, y_seed + max_shift, 3.0, Inf];
                    fit_P = lsqcurvefit(gauss2D, guess, cat(3,X,Y), sub, lb, ub, opts);
                    pos_fit(s, 1, f) = x_lo + fit_P(2) - 1;
                    pos_fit(s, 2, f) = y_lo + fit_P(3) - 1;
                end
            end
        end
    end
end
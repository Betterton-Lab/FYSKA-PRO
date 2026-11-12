function [Kymograph, Kymo_opt, x_axis, t_axis] = makeAdvancedKymograph(movie3D, pos_spots, ch_idx, cfg)
    % MAKEADVANCEDKYMOGRAPH Generates single-channel kymographs and overlays.

    ch_name   = cfg.channel_names{ch_idx};
    AbsEndExt = getCfgField(cfg, 'ROI_end_extension_length', 10);
    kymo_cfg  = getKymoCfg(cfg);

    %% 1. SPATIAL AND TEMPORAL AXIS SETUP
    has_spb      = squeeze(sum(sum(pos_spots(1:2, :, :), 1), 2));
    first_frame  = find(~isnan(has_spb), 1, 'first');
    last_frame   = find(~isnan(has_spb), 1, 'last');
    total_frames = last_frame - first_frame + 1;

    axis_21 = squeeze(pos_spots(2,:,:) - pos_spots(1,:,:));
    max_len21 = ceil(max(sqrt(sum((axis_21.^2), 1)), [], 'omitnan'));

    % Search globally for any valid protrusion coordinate in the active frames.
    % If none exists (including a true 2-row pos_spots array), use the
    % original fixed-SPB1 two-spot kymograph geometry from makeKymograph.m.
    has_prot_any = false;
    if size(pos_spots, 1) >= 3
        prot_range = pos_spots(3, :, first_frame:last_frame);
        has_prot_any = any(reshape(all(~isnan(prot_range), 2), [], 1));
    end

    if has_prot_any
        % --- Existing 3-spot geometry (unchanged) ---
        axis_23 = squeeze(pos_spots(2,:,:) - pos_spots(3,:,:));
        max_len23     = ceil(max(sqrt(sum((axis_23.^2), 1)), [], 'omitnan'));
        interp_step23 = max_len23 + AbsEndExt;
        interp_step21 = max_len21 + AbsEndExt;
        total_cols    = interp_step21 + max(0, interp_step23 - 1);
    else
        % --- Original 2-spot geometry: SPB1 fixed, extension on both ends ---
        total_cols = max_len21 + 2 * AbsEndExt;
    end

    % Configure Spatial Axis (x_axis)
    dx_val = getCfgField(cfg, 'micron_per_pix', 1);
    switch lower(kymo_cfg.x_unit)
        case 'um'
            x_axis = (0 : total_cols - 1) * dx_val;
        case 'pixel'
            x_axis = 1 : total_cols;
        otherwise
            x_axis = (0 : total_cols - 1) * dx_val;
    end

    % Configure Temporal Axis (t_axis)
    dt_val = getCfgField(cfg, 'time_step', 1);
    switch lower(kymo_cfg.t_unit)
        case 'min'
            t_axis = (0 : total_frames - 1) * dt_val / 60;
        case 's'
            t_axis = (0 : total_frames - 1) * dt_val;
        case 'frame'
            t_axis = 1 : total_frames;
        otherwise
            t_axis = (0 : total_frames - 1) * dt_val / 60;
    end

    %% 2. PROFILE EXTRACTION
    Kymograph = zeros(total_frames, total_cols);
    spots_pos = zeros(total_frames, 3);

    for f = first_frame:last_frame
        row = f - first_frame + 1;
        
        if ndims(movie3D) == 4
            img_MIP = max(imgaussfilt3(movie3D(:,:,:,f)), [], 3);
        else
            img_MIP = movie3D(:,:,f);
        end

        s1 = pos_spots(1,:,f); s2 = pos_spots(2,:,f);
        if any(isnan(s1)) || any(isnan(s2)), continue; end

        if has_prot_any
            % =============================================================
            % 3-SPOT GEOMETRY (UNCHANGED)
            % =============================================================
            s3 = pos_spots(3,:,f);

            % --- Segment 21 (SPB 2 to SPB 1) ---
            len21 = norm(s1 - s2); if len21 == 0, len21 = 1e-5; end
            ratio21  = max_len21 / len21;
            end_pos1 = s2 + (s1 - s2) * ratio21 + (s1 - s2) / len21 * AbsEndExt;

            x_list21 = linspace(s2(1), end_pos1(1), interp_step21);
            y_list21 = linspace(s2(2), end_pos1(2), interp_step21);
            line21      = interp2(img_MIP, x_list21, y_list21, 'cubic');

            % --- Segment 23 (SPB 2 to Protrusion Spot 3) ---
            is_s3_valid = ~any(isnan(s3));
            if is_s3_valid
                len23 = norm(s3 - s2); if len23 == 0, len23 = 1e-5; end
                dir23    = (s3 - s2) / len23;
                ratio23  = max_len23 / len23;
                end_pos3 = s2 + (s3 - s2) * ratio23 + dir23 * AbsEndExt;
            else
                dir21    = (s2 - s1) / len21; dir23 = dir21;
                end_pos3 = s2 + dir23 * (max_len23 + AbsEndExt);
            end

            x_list23 = linspace(s2(1), end_pos3(1), interp_step23);
            y_list23 = linspace(s2(2), end_pos3(2), interp_step23);
            line23      = interp2(img_MIP, x_list23, y_list23, 'cubic');

            tot_len = norm(end_pos1 - s2) + norm(end_pos3 - s2);
            spots_pos(row, 1) = norm(s1 - end_pos1) / tot_len;
            spots_pos(row, 2) = norm(s2 - end_pos1) / tot_len;
            spots_pos(row, 3) = ternary(is_s3_valid, (norm(s2 - end_pos1) + norm(s3 - s2)) / tot_len, NaN);

            Kymograph(row, :) = [flip(line21), line23(2:end)];
        else
            % =============================================================
            % 2-SPOT GEOMETRY (from original makeKymograph.m)
            % Fix SPB1 at a constant offset from the left edge. SPB2 moves
            % according to spindle length. Keep AbsEndExt on both ends.
            % =============================================================
            len12 = norm(s2 - s1); if len12 == 0, len12 = 1e-5; end
            dir12 = (s2 - s1) / len12;

            start_pos = s1 - dir12 * AbsEndExt;
            end_pos   = s1 + dir12 * (max_len21 + AbsEndExt);

            x_list = linspace(start_pos(1), end_pos(1), total_cols);
            y_list = linspace(start_pos(2), end_pos(2), total_cols);
            intensity_line = interp2(img_MIP, x_list, y_list, 'cubic');

            tot_len = norm(end_pos - start_pos);
            spots_pos(row, 1) = norm(s1 - start_pos) / tot_len;
            spots_pos(row, 2) = norm(s2 - start_pos) / tot_len;
            spots_pos(row, 3) = NaN;

            Kymograph(row, :) = intensity_line;
        end
    end

    out_base = fullfile(cfg.out_data_path, sprintf('%s_%s', cfg.data_name, ch_name));

    % Log kymograph dimensions (pixels/frames and total physical extent)
    W_px  = size(Kymograph, 2);
    H_fr  = size(Kymograph, 1);
    W_um  = W_px * getCfgField(cfg, 'micron_per_pix', 1);
    H_min = H_fr * getCfgField(cfg, 'time_step', 1) / 60;
    log_path = fullfile(cfg.out_data_path, 'kymograph_dim.txt');
    if ~exist(log_path, 'file')
        fid = fopen(log_path, 'w');
        fprintf(fid, '%-36s %8s %10s %12s %12s\n', ...
            'Kymograph', 'W_px', 'H_frames', 'W_um', 'H_min');
        fclose(fid);
    end
    fid = fopen(log_path, 'a');
    fprintf(fid, '%-36s %8d %10d %12.6f %12.6f\n', ...
        sprintf('%s_%s', cfg.data_name, ch_name), W_px, H_fr, W_um, H_min);
    fclose(fid);

    %% 3. EXPORT OUTPUT 1: KYMOGRAPH + OVERLAY
    sp_colors = parseMovieSpotColors(cfg);
    
    fig_dots = buildBaseFigure(x_axis, t_axis, Kymograph, cfg);
    hold on;
    plot(spots_pos(:, 1) * x_axis(end), t_axis, '.', 'Color', sp_colors(1,:), 'MarkerSize', 12);
    plot(spots_pos(:, 2) * x_axis(end), t_axis, '.', 'Color', sp_colors(2,:), 'MarkerSize', 12);
    
    valid_s3 = ~isnan(spots_pos(:, 3));
    if any(valid_s3)
        plot(spots_pos(valid_s3, 3) * x_axis(end), t_axis(valid_s3), '.', 'Color', sp_colors(3,:), 'MarkerSize', 12);
    end

    if kymo_cfg.show_axis
        cb = colorbar;
        cb.Label.String   = sprintf('%s intensity (a.u)', ch_name);
        lbl_sz = ternary(~isempty(kymo_cfg.label_size), kymo_cfg.label_size, getCfgField(cfg.plot, 'label_size', 14));
        cb.Label.FontSize = lbl_sz;
    end

    exportgraphics(fig_dots, [out_base, '_kymograph+dots.png'], 'Resolution', 400);
    close(fig_dots);

    %% 4. EXPORT OUTPUT 2: OPTIMIZED SINGLE-CHANNEL KYMOGRAPH
    c_bounds = getChannelContrast(cfg, ch_idx);
    Kymo_opt = applySmartContrast(Kymograph, c_bounds);

    fig_opt = buildBaseFigure(x_axis, t_axis, Kymo_opt, cfg);
    exportgraphics(fig_opt, [out_base, '_optimized.png'], 'Resolution', 400);
    set(fig_opt, 'Visible', 'on');
    savefig(fig_opt, [out_base, '_optimized.fig']);
    save([out_base, '_kymograph.mat'], 'Kymograph', 'Kymo_opt', 'spots_pos');
    close(fig_opt);
end

%% LOCAL HELPER FUNCTIONS
function kymo_cfg = getKymoCfg(cfg)
    kymo_cfg = struct();
    if isfield(cfg, 'plot') && isfield(cfg.plot, 'kymo')
        kymo_cfg = cfg.plot.kymo;
    end
    if ~isfield(kymo_cfg, 'show_axis')   || isempty(kymo_cfg.show_axis),   kymo_cfg.show_axis   = true;     end
    if ~isfield(kymo_cfg, 'x_unit')      || isempty(kymo_cfg.x_unit),      kymo_cfg.x_unit      = 'um';     end
    if ~isfield(kymo_cfg, 't_unit')      || isempty(kymo_cfg.t_unit),      kymo_cfg.t_unit      = 'min';    end
    if ~isfield(kymo_cfg, 'x_label'),    kymo_cfg.x_label   = 'auto';   end
    if ~isfield(kymo_cfg, 't_label'),    kymo_cfg.t_label   = 'auto';   end
    if ~isfield(kymo_cfg, 'font_size'),  kymo_cfg.font_size  = [];      end
    if ~isfield(kymo_cfg, 'label_size'), kymo_cfg.label_size = [];      end
    if ~isfield(kymo_cfg, 'font_weight'),kymo_cfg.font_weight = [];     end
    if ~isfield(kymo_cfg, 'x_tick_step'), kymo_cfg.x_tick_step = [];    end
    if ~isfield(kymo_cfg, 'y_tick_step'), kymo_cfg.y_tick_step = [];    end
end

function sp_colors = parseMovieSpotColors(cfg)
    sp_colors = [1, 0, 0; 0, 1, 0; 0, 0, 1];
    if isfield(cfg, 'plot') && isfield(cfg.plot, 'movie') && isfield(cfg.plot.movie, 'spot_colors')
        if ~isempty(cfg.plot.movie.spot_colors)
            sp_colors = cfg.plot.movie.spot_colors;
        end
    end
end

function c_bounds = getChannelContrast(cfg, ch_idx)
    if isfield(cfg, 'plot') && isfield(cfg.plot, 'kymo_contrast')
        kc = cfg.plot.kymo_contrast;
        if isstruct(kc)
            if ch_idx == 1 && isfield(kc, 'red'), c_bounds = kc.red;
            elseif ch_idx == 2 && isfield(kc, 'green'), c_bounds = kc.green;
            else, c_bounds = [0.05, 0.98]; end
        elseif ismatrix(kc) && size(kc, 1) >= ch_idx
            c_bounds = kc(ch_idx, :);
        else, c_bounds = [0.05, 0.98]; end
    else, c_bounds = [0.05, 0.98]; end
end

function img_opt = applySmartContrast(img, limits)
    img_double = double(img);
    nan_mask   = isnan(img_double);
    img_double(nan_mask) = 0;

    if max(limits) <= 1
        img_opt = imadjust(rescale(img_double), limits, []);
    else
        raw_min = limits(1); raw_max = limits(2);
        img_opt = (img_double - raw_min) / (raw_max - raw_min);
        img_opt = max(0, min(1, img_opt));
    end
    img_opt(nan_mask) = 0;
end

function fig = buildBaseFigure(x_axis, t_axis, img, cfg)
    fig = figure('Units', getCfgField(cfg.plot, 'fig_units', 'pixels'), ...
                 'Position', getCfgField(cfg.plot, 'fig_pos', [100 100 400 600]), ...
                 'Color', 'w', 'Visible', 'off');
    imagesc(x_axis, t_axis, img);
    colormap gray;
    set(gca, 'Color', 'k');
    
    applyKymoAxisFormatting(gca, x_axis, t_axis, cfg);
end

function applyKymoAxisFormatting(ax, x_axis, t_axis, cfg)
    kymo_cfg = getKymoCfg(cfg);
    
    % Enforce 1:1 pixel aspect ratio (square pixels)
    dx = mean(diff(x_axis)); if isempty(dx) || isnan(dx) || dx == 0, dx = 1; end
    dt = mean(diff(t_axis)); if isempty(dt) || isnan(dt) || dt == 0, dt = 1; end
    daspect(ax, [dx, dt, 1]);

    if ~kymo_cfg.show_axis
        axis(ax, 'off');
        return;
    end

    axis(ax, 'on');

    base_font_sz  = getCfgField(cfg.plot, 'font_size', 12);
    base_lbl_sz   = getCfgField(cfg.plot, 'label_size', 14);
    base_font_wt  = getCfgField(cfg.plot, 'font_weight', 'normal');
    font_name     = getCfgField(cfg.plot, 'font_name', 'Helvetica');
    line_width    = getCfgField(cfg.plot, 'line_width', 1.5);
    
    font_sz  = ternary(~isempty(kymo_cfg.font_size),   kymo_cfg.font_size,   base_font_sz);
    label_sz = ternary(~isempty(kymo_cfg.label_size),  kymo_cfg.label_size,  base_lbl_sz);
    font_wt  = ternary(~isempty(kymo_cfg.font_weight), kymo_cfg.font_weight, base_font_wt);

    set(ax, 'FontSize', font_sz, 'LineWidth', line_width, 'FontWeight', font_wt, 'FontName', font_name);

    if ~isempty(kymo_cfg.x_tick_step)
        xticks(ax, 0:kymo_cfg.x_tick_step:max(x_axis));
    end
    if ~isempty(kymo_cfg.y_tick_step)
        yticks(ax, 0:kymo_cfg.y_tick_step:max(t_axis));
    end
    
    % Resolve X Label
    if ischar(kymo_cfg.x_label) || isstring(kymo_cfg.x_label)
        if strcmpi(kymo_cfg.x_label, 'auto')
            switch lower(kymo_cfg.x_unit)
                case 'um',    x_lbl = 'Distance (\mum)';
                case 'pixel', x_lbl = 'Distance (pixels)';
                otherwise,    x_lbl = 'Distance';
            end
        else
            x_lbl = kymo_cfg.x_label;
        end
    else
        x_lbl = 'Distance (\mum)';
    end

    % Resolve T Label
    if ischar(kymo_cfg.t_label) || isstring(kymo_cfg.t_label)
        if strcmpi(kymo_cfg.t_label, 'auto')
            switch lower(kymo_cfg.t_unit)
                case 'min',   t_lbl = 'Time (min)';
                case 's',     t_lbl = 'Time (s)';
                case 'frame', t_lbl = 'Frame';
                otherwise,    t_lbl = 'Time';
            end
        else
            t_lbl = kymo_cfg.t_label;
        end
    else
        t_lbl = 'Time (min)';
    end

    xlabel(ax, x_lbl, 'FontSize', label_sz, 'FontName', font_name, 'FontWeight', font_wt);
    ylabel(ax, t_lbl, 'FontSize', label_sz, 'FontName', font_name, 'FontWeight', font_wt);
end

function val = getCfgField(cfg_struct, fieldname, default_val)
    if isstruct(cfg_struct) && isfield(cfg_struct, fieldname) && ~isempty(cfg_struct.(fieldname))
        val = cfg_struct.(fieldname); 
    else
        val = default_val; 
    end
end

function out = ternary(cond, true_val, false_val)
    if cond, out = true_val; else, out = false_val; end
end
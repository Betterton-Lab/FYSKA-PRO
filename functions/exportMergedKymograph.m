function exportMergedKymograph(kymo1, kymo2, x_axis, t_axis, cfg)
    % EXPORTMERGEDKYMOGRAPH Generates and saves a dual-channel overlay kymograph

    % 1. Retrieve contrast bounds for each channel
    c1_bounds = getChannelContrast(cfg, 1);
    c2_bounds = getChannelContrast(cfg, 2);

    % 2. Normalize single-channel kymographs to strictly [0, 1] range
    kymo1_opt = applySmartContrast(kymo1, c1_bounds, 'Ch1 (Red)');
    kymo2_opt = applySmartContrast(kymo2, c2_bounds, 'Ch2 (Green)');

    % Enforce zero (black) for out-of-bounds NaN positions
    kymo1_opt(isnan(kymo1_opt)) = 0;
    kymo2_opt(isnan(kymo2_opt)) = 0;

    % 3. Construct 3D RGB image (Red = Channel 1, Green = Channel 2, Blue = 0)
    rgb_kymo = cat(3, kymo1_opt, kymo2_opt, zeros(size(kymo1_opt)));

    % 4. Build Figure
    fig_merge = figure('Units', getCfgField(cfg.plot, 'fig_units', 'pixels'), ...
                       'Position', getCfgField(cfg.plot, 'fig_pos', [100 100 400 600]), ...
                       'Color', 'w', 'Visible', 'off');
    imagesc(x_axis, t_axis, rgb_kymo);
    set(gca, 'Color', 'k');
    
    % 5. Apply Labels, Formatting & Aspect Ratio
    applyKymoAxisFormatting(gca, x_axis, t_axis, cfg);

    % 6. Save Figure (.PNG and .FIG)
    out_base = fullfile(cfg.out_data_path, sprintf('%s_merged_kymograph', cfg.data_name));

    % Log merged-kymograph dimensions
    W_px  = size(kymo1, 2);
    H_fr  = size(kymo1, 1);
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
        sprintf('%s_merged_kymograph', cfg.data_name), W_px, H_fr, W_um, H_min);
    fclose(fid);

    exportgraphics(fig_merge, [out_base, '.png'], 'Resolution', 400);
    set(fig_merge, 'Visible', 'on');
    savefig(fig_merge, [out_base, '.fig']);
    close(fig_merge);
    
    fprintf('Merged kymograph exported successfully:\n - %s.png\n', out_base);
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

function c_bounds = getChannelContrast(cfg, ch_idx)
    if isfield(cfg, 'plot') && isfield(cfg.plot, 'kymo_contrast')
        kc = cfg.plot.kymo_contrast;
        if isstruct(kc)
            if ch_idx == 1 && isfield(kc, 'red')
                c_bounds = kc.red;
            elseif ch_idx == 2 && isfield(kc, 'green')
                c_bounds = kc.green;
            else
                fn = fieldnames(kc);
                if ch_idx <= numel(fn)
                    c_bounds = kc.(fn{ch_idx});
                else
                    c_bounds = [0.05, 0.98];
                end
            end
        elseif ismatrix(kc) && size(kc, 1) >= ch_idx
            c_bounds = kc(ch_idx, :);
        else
            c_bounds = [0.05, 0.98];
        end
    else
        c_bounds = [0.05, 0.98];
    end
end

function img_opt = applySmartContrast(img, limits, ch_name)
    img_double = double(img);
    nan_mask   = isnan(img_double);
    img_double(nan_mask) = 0;
    
    img_min = min(img_double(~nan_mask));
    if isempty(img_min), img_min = 0; end
    img_max = max(img_double(~nan_mask));
    if isempty(img_max), img_max = 1; end
    
    fprintf('[%s] Data Range: [%.2f, %.2f] | Target Limits: [%.2f, %.2f]\n', ...
            ch_name, img_min, img_max, limits(1), limits(2));
    
    if img_max <= 1.0
        img_opt = img_double;
    elseif img_max < limits(1)
        warning('Max intensity (%.2f) is below limit (%.2f). Auto-scaling to image min/max to prevent black image.', img_max, limits(1));
        img_opt = (img_double - img_min) / max(1e-5, (img_max - img_min));
    else
        raw_min = limits(1);
        raw_max = limits(2);
        img_opt = (img_double - raw_min) / max(1e-5, (raw_max - raw_min));
    end
    
    img_opt = max(0, min(1, img_opt));
    img_opt(nan_mask) = 0;
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
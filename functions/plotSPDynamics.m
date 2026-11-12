function [lvt_data, protrusion_angle] = plotSPDynamics(pos_spots, cfg)
    % PLOTSPDYNAMICS Computes and plots Spindle Length, Protrusion Length, 
    % and Protrusion Angle over time based on tracked 3-spot positions.

    %% 1. EXTRACT CALIBRATION & BOUNDARIES
    total_frames   = size(pos_spots, 3);
    time_step      = getCfgField(cfg, 'time_step', 1);        % Seconds per frame
    micron_per_pix = getCfgField(cfg, 'micron_per_pix', 1);   % um per pixel
    
    if isempty(time_step), time_step = 1; end
    if isempty(micron_per_pix), micron_per_pix = 1; end

    first_frame = getCfgField(cfg, 'first_frame', 1);
    last_frame  = getCfgField(cfg, 'last_frame', total_frames);
    if isempty(first_frame), first_frame = 1; end
    if isempty(last_frame), last_frame = total_frames; end

    out_dir = getCfgField(cfg, 'out_data_path', pwd);
    if ~exist(out_dir, 'dir'), mkdir(out_dir); end

    time_min = (1:total_frames) * (time_step / 60); % Time array in minutes

    %% 2. CALCULATE SPINDLE & PROTRUSION LENGTHS
    spindle_len_um    = NaN(1, total_frames);
    protrusion_len_um = NaN(1, total_frames);

    for f = first_frame:last_frame
        % SPB1 to SPB2 (Spindle)
        if ~any(isnan(pos_spots(1,:,f))) && ~any(isnan(pos_spots(2,:,f)))
            vec_12_um = (pos_spots(2,:,f) - pos_spots(1,:,f)) * micron_per_pix;
            spindle_len_um(f) = norm(vec_12_um);
        end
        
        % SPB2 to Protrusion (Protrusion length)
        if ~any(isnan(pos_spots(2,:,f))) && ~any(isnan(pos_spots(3,:,f)))
            vec_23_um = (pos_spots(3,:,f) - pos_spots(2,:,f)) * micron_per_pix;
            protrusion_len_um(f) = norm(vec_23_um);
        end
    end

    %% 3. CALCULATE PROTRUSION ANGLE (> 0.5 um THRESHOLD)
    protrusion_angle = NaN(total_frames, 2);
    protrusion_angle(:, 1) = time_min';

    for f = first_frame:last_frame
        if ~isnan(protrusion_len_um(f)) && protrusion_len_um(f) > 0.5 && ...
           ~any(isnan(pos_spots(1,:,f))) && ~any(isnan(pos_spots(2,:,f)))
            
            vec_21 = squeeze(pos_spots(1,:,f) - pos_spots(2,:,f)); % Vector from SPB2 to SPB1
            vec_23 = squeeze(pos_spots(3,:,f) - pos_spots(2,:,f)); % Vector from SPB2 to Protrusion
            
            dot_prod = dot(vec_21, vec_23);
            norm_21  = norm(vec_21);
            norm_23  = norm(vec_23);
            
            if norm_21 > 0 && norm_23 > 0
                angle_rad = acos(min(max(dot_prod / (norm_21 * norm_23), -1), 1));
                protrusion_angle(f, 2) = 180 - rad2deg(angle_rad);
            end
        end
    end

    %% 4. EXTRACT PLOT STYLING PARAMETERS
    p_units   = getPlotField(cfg, 'fig_units', 'centimeters');
    p_pos     = getPlotField(cfg, 'fig_pos', [5, 5, 16, 12]);
    p_font    = getPlotField(cfg, 'font_name', 'Arial');
    p_fsize   = getPlotField(cfg, 'font_size', 20);
    p_lsize   = getPlotField(cfg, 'label_size', 20);
    p_weight  = getPlotField(cfg, 'font_weight', 'normal');
    p_lwidth  = getPlotField(cfg, 'line_width', 1.5);
    p_xstep   = getPlotField(cfg, 'x_tick_step', []);
    p_ystep   = getPlotField(cfg, 'y_tick_step', []);
    p_xlim    = getPlotField(cfg, 'x_lim', []);
    p_ylim    = getPlotField(cfg, 'y_lim', []);
    
    c_spindle = getPlotField(cfg, 'c_spindle', [0.7, 0.0, 0.0]);
    c_prot    = getPlotField(cfg, 'c_protrusion', [1.0, 0.2, 0.6]);
    c_angle   = getPlotField(cfg, 'c_angle', [0.9, 0.7, 0.2]);

    %% 5. PLOT 1: PROTRUSION ANGLE VS TIME
    fig_ang = figure('Name', 'Protrusion Angle vs Time', 'Units', p_units, 'Position', p_pos);
    
    plot(protrusion_angle(first_frame:last_frame, 1), protrusion_angle(first_frame:last_frame, 2), ...
         'Color', c_angle, 'LineStyle', '-', 'LineWidth', p_lwidth, 'DisplayName', 'Angle (deg)');
    
    xlabel('Time (min)', 'FontName', p_font, 'FontSize', p_lsize, 'FontWeight', p_weight);
    ylabel('Angle of protrusion', 'FontName', p_font, 'FontSize', p_lsize, 'FontWeight', p_weight);
    
    set(gca, 'FontName', p_font, 'FontSize', p_fsize, 'FontWeight', p_weight, 'LineWidth', 1);
    legend('Location', 'best', 'FontSize', p_fsize - 2); legend boxoff;
    % applyAxisTicks(gca, p_xstep, p_ystep);
    grid off;

    % Save Angle Data & Figures
    save(fullfile(out_dir, 'protrusion_angle.mat'), 'protrusion_angle');
    saveas(fig_ang, fullfile(out_dir, 'protrusion_angle.fig'));
    exportgraphics(fig_ang, fullfile(out_dir, 'protrusion_angle.png'), 'Resolution', 400);

    pause(1);

    %% 6. PLOT 2: LENGTH VS TIME (SPINDLE & PROTRUSION)
    fig_lvt = figure('Name', 'Length vs Time', 'Units', p_units, 'Position', p_pos);
    
    plot(time_min(first_frame:last_frame), spindle_len_um(first_frame:last_frame), ...
         'Color', c_spindle, 'LineStyle', '-', 'LineWidth', p_lwidth, 'DisplayName', 'Spindle length'); hold on;
    plot(time_min(first_frame:last_frame), protrusion_len_um(first_frame:last_frame), ...
         'Color', c_prot, 'LineStyle', ':', 'LineWidth', p_lwidth, 'DisplayName', 'Protrusion length');
    
    xlabel('Time (min)', 'FontName', p_font, 'FontSize', p_lsize, 'FontWeight', p_weight);
    ylabel('Length (\mum)', 'FontName', p_font, 'FontSize', p_lsize, 'FontWeight', p_weight);
    
    set(gca, 'FontName', p_font, 'FontSize', p_fsize, 'FontWeight', p_weight, 'LineWidth', 0.5);
    legend('Location', 'northwest', 'FontSize', p_fsize - 2); legend boxoff;
    if ~isempty(p_xlim), xlim(p_xlim); end
    if ~isempty(p_ylim), ylim(p_ylim); end
    applyAxisTicks(gca, p_xstep, p_ystep);
    grid off; hold off;

    % Save Length vs Time Data & Figures
    lvt_data = [time_min', spindle_len_um', protrusion_len_um'];
    save(fullfile(out_dir, 'lvt_plot_data.mat'), 'lvt_data');
    saveas(fig_lvt, fullfile(out_dir, 'lvt_plot_full.fig'));
    exportgraphics(fig_lvt, fullfile(out_dir, 'lvt_plot_full.png'), 'Resolution', 400);

    pause(1);

    %% 7. CLOSE FIGURES
    close([fig_ang, fig_lvt]);
end

%% LOCAL HELPER FUNCTIONS
function applyAxisTicks(ax, x_step, y_step)
    % Always keep the tick labels horizontal, even with automatic ticks.
    set(ax, 'XTickLabelRotation', 0, 'YTickLabelRotation', 0);

    if ~isempty(x_step)
        lim = xlim(ax);
        tick_vals = (ceil(lim(1) / x_step) * x_step):x_step:(floor(lim(2) / x_step) * x_step);
        if ~isempty(tick_vals), xticks(ax, tick_vals); end
    end

    if ~isempty(y_step)
        lim = ylim(ax);
        tick_vals = (ceil(lim(1) / y_step) * y_step):y_step:(floor(lim(2) / y_step) * y_step);
        if ~isempty(tick_vals), yticks(ax, tick_vals); end
    end
end

function val = getCfgField(cfg, fieldname, default_val)
    if isfield(cfg, fieldname) && ~isempty(cfg.(fieldname)), val = cfg.(fieldname); else, val = default_val; end
end

function val = getPlotField(cfg, fieldname, default_val)
    if isfield(cfg, 'plot') && isfield(cfg.plot, fieldname) && ~isempty(cfg.plot.(fieldname))
        val = cfg.plot.(fieldname);
    else
        val = default_val;
    end
end
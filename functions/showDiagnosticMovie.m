function showDiagnosticMovie(movies3D, pos_spots, cfg, varargin)
    % SHOWDIAGNOSTICMOVIE Renders interactive overlays, video files (.avi/.mp4),
    % multi-channel composite/grayscale displays, selective bounding boxes, and markers.

    %% 1. GLOBAL MASTER SWITCH CHECK
    if isfield(cfg, 'movie_on') && cfg.movie_on == 0
        disp('cfg.movie_on = 0. Skipping diagnostic movie export.');
        return;
    end

    %% 2. PARSE PARAMETERS & OVERRIDES
    p = parseMovieParams(cfg, varargin{:});

    % Get active frames
    has_spb      = squeeze(sum(sum(pos_spots(1:2, :, :), 1), 2));
    first_frame  = find(~isnan(has_spb), 1, 'first');
    last_frame   = find(~isnan(has_spb), 1, 'last');
    
    if isempty(first_frame), disp('No valid spot coordinates found.'); return; end

    % Prepare 2D stacks
    if ndims(movies3D{1}) == 4
        Ch1 = squeeze(max(movies3D{1}, [], 3));
        Ch2 = squeeze(max(movies3D{2}, [], 3));
    else
        Ch1 = movies3D{1}; Ch2 = movies3D{2};
    end

    [img_h, img_w, ~] = size(Ch1);
    [c_red, c_green]  = parseContrastLimits(cfg);

    % Axis spatial scaling
    use_micron = strcmpi(p.axis_unit, 'micron') && isfield(cfg, 'micron_per_pix') && ~isempty(cfg.micron_per_pix);
    scale_fac  = ternary(use_micron, cfg.micron_per_pix, 1.0);
    x_axis     = (1:img_w) * scale_fac;
    y_axis     = (1:img_h) * scale_fac;

    %% 3. CALCULATE LOI EXTENSIONS
    AbsEndExt = getCfgField(cfg, 'ROI_end_extension_length', 10);
    axis_21   = squeeze(pos_spots(2,:,:) - pos_spots(1,:,:));
    max_len21 = ceil(max(sqrt(sum((axis_21.^2), 1)), [], 'omitnan'));

    % Globally determine whether this cell has a protrusion track.
    % If not, use the legacy 2-spot fixed-SPB1 geometry.
    has_prot_any = false;
    max_len23    = 0;
    if size(pos_spots, 1) >= 3
        prot_x = pos_spots(3, 1, first_frame:last_frame);
        prot_y = pos_spots(3, 2, first_frame:last_frame);
        has_prot_any = any(~isnan(prot_x(:)) & ~isnan(prot_y(:)));

        if has_prot_any
            axis_23   = squeeze(pos_spots(3,:,:) - pos_spots(2,:,:));
            max_len23 = ceil(max(sqrt(sum((axis_23.^2), 1)), [], 'omitnan'));
        end
    end

    %% 4. VIDEO WRITER INITIALIZATION
    out_name = ternary(isempty(p.output_name), [cfg.data_name, '_movie'], p.output_name);
    mov_path = fullfile(cfg.out_data_path, [out_name, p.file_format]);

    if strcmpi(p.file_format, '.mp4')
        vid = VideoWriter(mov_path, 'MPEG-4');
        vid.Quality = 100;
    else
        vid = VideoWriter(mov_path, 'Motion JPEG AVI');
        vid.Quality = 100;
    end
    vid.FrameRate = p.replay_fps;
    open(vid);

    fig = figure('Name', 'Diagnostic Movie Renderer', 'Position', p.fig_pos, 'Color', 'w');

    %% 5. MAIN RENDERING LOOP
    for f = first_frame:last_frame
        r_img = AdjustContrastSmart(Ch1(:,:,f), c_red);
        g_img = AdjustContrastSmart(Ch2(:,:,f), c_green);

        % Composite Channels & Colormap Handling
        if isequal(p.channels, [1, 2])
            rgb_img  = cat(3, r_img, g_img, zeros(size(r_img)));
            ch_label = 'CH 1+2 (Merged)';
        else
            if isequal(p.channels, 1)
                I = r_img; ch_label = 'CH 1';
            else
                I = g_img; ch_label = 'CH 2';
            end

            switch lower(p.colormap)
                case 'red'
                    rgb_img = cat(3, I, zeros(size(I)), zeros(size(I)));
                case 'green'
                    rgb_img = cat(3, zeros(size(I)), I, zeros(size(I)));
                case 'blue'
                    rgb_img = cat(3, zeros(size(I)), zeros(size(I)), I);
                case {'gray', 'grey'}
                    rgb_img = cat(3, I, I, I);
                otherwise
                    try
                        cmap = feval(p.colormap, 256);
                        rgb_img = ind2rgb(uint8(I * 255), cmap);
                    catch
                        warning('Unknown colormap "%s". Defaulting to grayscale.', p.colormap);
                        rgb_img = cat(3, I, I, I);
                    end
            end
        end

        imagesc(x_axis, y_axis, rgb_img); axis image; hold on;

        s1 = pos_spots(1,:,f);
        s2 = pos_spots(2,:,f);
        if size(pos_spots, 1) >= 3
            s3 = pos_spots(3,:,f);
        else
            s3 = [NaN, NaN];
        end

        % --- DRAW LOI AXIS (Only when LineWidth > 0) ---
        if p.line_width > 0 && ~any(isnan(s1)) && ~any(isnan(s2))
            len21 = norm(s1 - s2); if len21 == 0, len21 = 1e-5; end

            if has_prot_any
                % 3-SPOT GEOMETRY: keep SPB2 as the central junction.
                ratio21  = max_len21 / len21;
                end_pos1 = s2 + (s1 - s2) * ratio21 + (s1 - s2) / len21 * AbsEndExt;

                is_s3_valid = ~any(isnan(s3));
                if is_s3_valid
                    len23 = norm(s3 - s2); if len23 == 0, len23 = 1e-5; end
                    dir23    = (s3 - s2) / len23;
                    ratio23  = max_len23 / len23;
                    end_pos3 = s2 + (s3 - s2) * ratio23 + dir23 * AbsEndExt;
                else
                    dir21    = (s2 - s1) / len21;
                    end_pos3 = s2 + dir21 * (max_len23 + AbsEndExt);
                end

                % Segment 1
                plot([end_pos1(1), s2(1)] * scale_fac, [end_pos1(2), s2(2)] * scale_fac, ...
                     '-', 'Color', p.loi_spb_color, 'LineWidth', p.line_width);

                % Segment 2
                loi_seg2_color = ternary(is_s3_valid, p.loi_prot_color, p.loi_spb_color);
                plot([s2(1), end_pos3(1)] * scale_fac, [s2(2), end_pos3(2)] * scale_fac, ...
                     '-', 'Color', loi_seg2_color, 'LineWidth', p.line_width);
            else
                % 2-SPOT GEOMETRY: legacy fixed-SPB1 alignment used by makeKymograph.m.
                dir12    = (s2 - s1) / len21;
                end_pos1 = s1 - dir12 * AbsEndExt;
                end_pos2 = s1 + dir12 * (max_len21 + AbsEndExt);

                plot([end_pos1(1), end_pos2(1)] * scale_fac, [end_pos1(2), end_pos2(2)] * scale_fac, ...
                     '-', 'Color', p.loi_spb_color, 'LineWidth', p.line_width);
            end
        end

        % --- DRAW SELECTIVE ORIENTED BOUNDING BOXES & REGIONS ---
        if p.box_size > 0
            bw        = p.box_size;
            lw_square = 2.0; % Slightly thicker linewidth for square spot boxes
            lw_region = 1.3; % Linewidth for intermediate region rectangles

            % Compute Spindle Axis unit vectors (1 -> 2)
            has_spb12 = ~any(isnan(s1)) && ~any(isnan(s2));
            if has_spb12
                v12   = s2 - s1;
                len12 = norm(v12); if len12 == 0, len12 = 1e-5; end
                u12   = v12 / len12;
                n12   = [-u12(2), u12(1)];
            end

            % Compute Protrusion Axis unit vectors (2 -> 3)
            has_spb23 = ~any(isnan(s2)) && ~any(isnan(s3));
            if has_spb23
                v23   = s3 - s2;
                len23 = norm(v23); if len23 == 0, len23 = 1e-5; end
                u23   = v23 / len23;
                n23   = [-u23(2), u23(1)];
            end

            % =========================================================
            % LAYER 1 (BOTTOM): SPOT SQUARE BOXES (SPB1, SPB2, PROTRUSION TIP)
            % =========================================================
            
            % Line 1: Far SPB (SPB1 square)
            clr1 = getBoxColor(p.box_colors, 1);
            if ~isempty(clr1) && has_spb12
                drawOrientedBox(s1, u12, n12, bw, bw, clr1, scale_fac, lw_square);
            end

            % Line 3: SPB2 (Spindle alignment - sour green square)
            clr3 = getBoxColor(p.box_colors, 3);
            if ~isempty(clr3) && has_spb12
                drawOrientedBox(s2, u12, n12, bw, bw, clr3, scale_fac, lw_square);
            end

            % Line 4: SPB2 (Protrusion alignment - aqua green square)
            clr4 = getBoxColor(p.box_colors, 4);
            if ~isempty(clr4) && has_spb23
                drawOrientedBox(s2, u23, n23, bw, bw, clr4, scale_fac, lw_square);
            end

            % Line 6: Protrusion Tip (blue square)
            clr6 = getBoxColor(p.box_colors, 6);
            if ~isempty(clr6) && has_spb23
                drawOrientedBox(s3, u23, n23, bw, bw, clr6, scale_fac, lw_square);
            end

            % =========================================================
            % LAYER 2 (TOP): INTERMEDIATE ZONE RECTANGLE OVERLAYS
            % =========================================================
            
            % Line 2: Mid-spindle region (rectangle spanning SPB1 to SPB2)
            clr2 = getBoxColor(p.box_colors, 2);
            if ~isempty(clr2) && has_spb12
                p_start = s1 + u12 * bw;
                p_end   = s2 - u12 * bw;
                if len12 > 2 * bw
                    drawOrientedRegion(p_start, p_end, n12, bw, clr2, scale_fac, lw_region);
                else
                    drawOrientedRegion(s1, s2, n12, bw, clr2, scale_fac, lw_region);
                end
            end

            % Line 5: Mid-protrusion region (rectangle spanning SPB2 to Tip)
            clr5 = getBoxColor(p.box_colors, 5);
            if ~isempty(clr5) && has_spb23
                p_start = s2 + u23 * bw;
                p_end   = s3 - u23 * bw;
                if len23 > 2 * bw
                    drawOrientedRegion(p_start, p_end, n23, bw, clr5, scale_fac, lw_region);
                else
                    drawOrientedRegion(s2, s3, n23, bw, clr5, scale_fac, lw_region);
                end
            end
        end

        % --- DRAW SPOT MARKERS ---
        show_markers = ~isempty(p.spot_marker) && ...
                       ~strcmpi(strtrim(p.spot_marker), 'none') && ...
                       ~strcmpi(strtrim(p.spot_marker), '') && ...
                       p.spot_size > 0;

        if show_markers
            if ~any(isnan(s1))
                plot(s1(1)*scale_fac, s1(2)*scale_fac, p.spot_marker, ...
                     'Color', p.spot_colors(1,:), 'LineWidth', 2, 'MarkerSize', p.spot_size);
            end
            if ~any(isnan(s2))
                plot(s2(1)*scale_fac, s2(2)*scale_fac, p.spot_marker, ...
                     'Color', p.spot_colors(2,:), 'LineWidth', 2, 'MarkerSize', p.spot_size);
            end
            if ~any(isnan(s3))
                plot(s3(1)*scale_fac, s3(2)*scale_fac, p.spot_marker, ...
                     'Color', p.spot_colors(3,:), 'LineWidth', 2, 'MarkerSize', p.spot_size);
            end
        end

        % --- TITLE & AXIS FORMATTING ---
        if p.show_title
            title(sprintf('Cell: %s | %s | Frame %d', cfg.data_name, ch_label, f), ...
                  'Interpreter', 'none', ...
                  'FontSize', cfg.plot.font_size, ...
                  'FontName', cfg.plot.font_name, ...
                  'FontAngle', 'normal');
        end

        if p.show_axis_labels
            unit_str = ternary(use_micron, '(\mum)', '(pixels)');
            xlabel(['Distance ', unit_str], ...
                   'FontSize', cfg.plot.label_size, ...
                   'FontName', cfg.plot.font_name, ...
                   'FontAngle', 'normal');
            ylabel(['Distance ', unit_str], ...
                   'FontSize', cfg.plot.label_size, ...
                   'FontName', cfg.plot.font_name, ...
                   'FontAngle', 'normal');
        end

        % Set limits before assigning fixed ticks.
        xlim([x_axis(1), x_axis(end)]);
        ylim([y_axis(1), y_axis(end)]);

        if ~p.show_axis_ticks
            set(gca, 'XTick', [], 'YTick', []);
        else
            set(gca, ...
                'FontSize', cfg.plot.font_size, ...
                'LineWidth', cfg.plot.line_width, ...
                'FontName', cfg.plot.font_name, ...
                'FontAngle', 'normal');

            % Force all tick-label text to remain upright/horizontal.
            xtickangle(0);
            ytickangle(0);

            % Optional fixed movie/snapshot tick spacing.  Units follow
            % cfg.plot.movie.axis_unit: pixels for 'pixels', microns for 'micron'.
            if ~isempty(p.x_tick_step) && p.x_tick_step > 0
                x0 = ceil(x_axis(1) / p.x_tick_step) * p.x_tick_step;
                xticks(x0:p.x_tick_step:x_axis(end));
            end

            if ~isempty(p.y_tick_step) && p.y_tick_step > 0
                y0 = ceil(y_axis(1) / p.y_tick_step) * p.y_tick_step;
                yticks(y0:p.y_tick_step:y_axis(end));
            end
        end

        if p.colorbar, colorbar; end

        set(gca, 'Color', 'k');

        hold off; drawnow;
        writeVideo(vid, getframe(gcf));

        % --- SAVE SNAPSHOTS ---
        if ~isempty(p.snapshots) && ismember(f, p.snapshots)
            snap_path = fullfile(cfg.out_data_path, sprintf('%s_frame_%03d.png', out_name, f));
            exportgraphics(fig, snap_path, 'Resolution', 300);
            fprintf('Publication snapshot saved: %s\n', snap_path);
        end

        pause(1 / p.display_fps);
    end

    close(vid);
    if ishandle(fig), close(fig); end
    fprintf('Diagnostic video export completed:\n%s\n', mov_path);
end

%% HELPER FUNCTIONS
function drawOrientedBox(center, u, n, w_along, w_perp, color, scale_fac, lw)
    if nargin < 8, lw = 2.0; end
    c1 = center - u*w_along - n*w_perp;
    c2 = center + u*w_along - n*w_perp;
    c3 = center + u*w_along + n*w_perp;
    c4 = center - u*w_along + n*w_perp;
    pts = [c1; c2; c3; c4; c1] * scale_fac;
    plot(pts(:,1), pts(:,2), '-', 'Color', color, 'LineWidth', lw);
end

function drawOrientedRegion(p_start, p_end, n, w_perp, color, scale_fac, lw)
    if nargin < 7, lw = 1.3; end
    c1 = p_start - n*w_perp;
    c2 = p_end   - n*w_perp;
    c3 = p_end   + n*w_perp;
    c4 = p_start + n*w_perp;
    pts = [c1; c2; c3; c4; c1] * scale_fac;
    plot(pts(:,1), pts(:,2), '-', 'Color', color, 'LineWidth', lw);
end

function clr = getBoxColor(box_colors, idx)
    clr = [];
    if iscell(box_colors)
        if idx <= length(box_colors) && ~isempty(box_colors{idx})
            c = box_colors{idx};
            if ~any(isnan(c)), clr = c; end
        end
    elseif isnumeric(box_colors)
        if idx <= size(box_colors, 1)
            c = box_colors(idx, :);
            if ~any(isnan(c)), clr = c; end
        end
    end
end

function p = parseMovieParams(cfg, varargin)
    p.channels         = getMovieField(cfg, 'channels', [1, 2]);
    p.colormap         = getCfgField(cfg.plot, 'colormap', 'gray');
    p.line_width       = getMovieField(cfg, 'line_width', 1.5);
    p.box_size         = getMovieField(cfg, 'box_size', 0);
    p.box_colors       = getMovieField(cfg, 'box_colors', {[0.9,0,0], [1,0.9,0], [0.5,0.9,0], [0.2,0.8,0.4], [0,0.7,0.9], [0,0.1,0.9]});
    p.spot_colors      = getMovieField(cfg, 'spot_colors', [1,0,0; 0,1,0; 0,0,1]);
    p.spot_marker      = getMovieField(cfg, 'spot_marker', 'o');
    p.spot_size        = getMovieField(cfg, 'spot_size', 8);
    p.loi_spb_color    = getMovieField(cfg, 'loi_spb_color', [1, 1, 0]);
    p.loi_prot_color   = getMovieField(cfg, 'loi_prot_color', [0, 1, 1]);
    p.colorbar         = getMovieField(cfg, 'colorbar', false);
    p.display_fps      = getMovieField(cfg, 'display_fps', 15);
    p.replay_fps       = getMovieField(cfg, 'replay_fps', 10);
    p.file_format      = getMovieField(cfg, 'file_format', '.avi');
    p.output_name      = getMovieField(cfg, 'output_name', '');
    p.snapshots        = getMovieField(cfg, 'snapshots', []);
    p.show_title       = getMovieField(cfg, 'show_title', true);
    p.show_axis_ticks  = getMovieField(cfg, 'show_axis_ticks', true);
    p.show_axis_labels = getMovieField(cfg, 'show_axis_labels', true);
    p.axis_unit        = getMovieField(cfg, 'axis_unit', 'micron');
    p.x_tick_step      = getMovieField(cfg, 'x_tick_step', []);
    p.y_tick_step      = getMovieField(cfg, 'y_tick_step', []);
    p.fig_pos          = getMovieField(cfg, 'fig_pos', [100, 100, 800, 600]);

    for k = 1:2:length(varargin)
        key = varargin{k}; val = varargin{k+1};
        if isfield(p, key), p.(key) = val; end
    end
end

function val = getMovieField(cfg, fieldname, default_val)
    if isfield(cfg, 'plot') && isfield(cfg.plot, 'movie') && isfield(cfg.plot.movie, fieldname) && ~isempty(cfg.plot.movie.(fieldname))
        val = cfg.plot.movie.(fieldname);
    else
        val = default_val;
    end
end

function val = getCfgField(struct_obj, fieldname, default_val)
    if isfield(struct_obj, fieldname) && ~isempty(struct_obj.(fieldname))
        val = struct_obj.(fieldname);
    else
        val = default_val;
    end
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
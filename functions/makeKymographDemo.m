function [Kymograph, Kymo_opt, x_axis, t_axis] = makeKymographDemo(movies3D, pos_spots, ch_idx, cfg)
% MAKEKYMOGRAPHDEMO Drop-in analysis wrapper with one demo per channel.
% Pass the entire movies3D CELL array (not movies3D{c}) from main_FYSKA:
% [kymo_raw{c}, kymo_opt{c}, x_ax, t_ax] = ...
%     makeKymographDemo(movies3D, pos_spots_final, c, cfg);
%
% Original advanced kymograph output, files, and numerical calculations
% remain unchanged. Each channel gets a demo with a merged left panel.
%
% Local demo-only switch (no cfg edits needed):
    show_current_time_line = false;

    if ~iscell(movies3D)
        error('makeKymographDemo:Input', ...
            'Pass movies3D (cell array), not movies3D{c}, to show merged channels.');
    end

    [Kymograph, Kymo_opt, x_axis, t_axis] = ...
        makeAdvancedKymograph(movies3D{ch_idx}, pos_spots, ch_idx, cfg);

    if numel(movies3D) < 2
        warning('makeKymographDemo:Channels', 'Two channels are needed for a merged movie.');
        return;
    end

    % Match frame range and two-/three-spot sampling geometry.
    has_spb = squeeze(sum(sum(pos_spots(1:2,:,:), 1), 2));
    first_frame = find(~isnan(has_spb), 1, 'first');
    last_frame = find(~isnan(has_spb), 1, 'last');
    if isempty(first_frame), return; end
    extension = fieldOr(cfg, 'ROI_end_extension_length', 10);
    d21 = squeeze(pos_spots(2,:,:) - pos_spots(1,:,:));
    max_len21 = ceil(max(sqrt(sum(d21.^2, 1)), [], 'omitnan'));
    has_prot = false;
    if size(pos_spots,1) >= 3
        pr = pos_spots(3,:,first_frame:last_frame);
        has_prot = any(reshape(all(~isnan(pr), 2), [], 1));
    end
    if has_prot
        d23 = squeeze(pos_spots(2,:,:) - pos_spots(3,:,:));
        max_len23 = ceil(max(sqrt(sum(d23.^2,1)), [], 'omitnan'));
    end

    mp = fieldOr(cfg.plot, 'movie', struct());
    kp = fieldOr(cfg.plot, 'kymo', struct()); % Axis units only; not demo font sizes.
    font_name = fieldOr(cfg.plot, 'font_name', 'Arial');
    font_sz = fieldOr(cfg.plot, 'font_size', 14);
    label_sz = fieldOr(cfg.plot, 'label_size', 14);
    font_wt = fieldOr(cfg.plot, 'font_weight', 'normal');
    line_w = fieldOr(mp, 'line_width', 1.5);
    spot_colors = fieldOr(mp, 'spot_colors', [1 0 0; 0 1 0; 0 0 1]);
    spot_marker = fieldOr(mp, 'spot_marker', 'o');
    spot_size = fieldOr(mp, 'spot_size', 8);
    spb_color = fieldOr(mp, 'loi_spb_color', [1 1 0]);
    prot_color = fieldOr(mp, 'loi_prot_color', [0 1 1]);

    ch1 = toProjection(movies3D{1});
    ch2 = toProjection(movies3D{2});
    [height, width, ~] = size(ch1);
    if ~isequal(size(ch1,1),size(ch2,1)) || ~isequal(size(ch1,2),size(ch2,2))
        error('makeKymographDemo:Dimensions','Merged movie channels must have equal XY dimensions.');
    end
    [red_limits, green_limits] = movieContrast(cfg);
    scale = 1;
    use_um = strcmpi(fieldOr(mp,'axis_unit','pixels'),'micron') && ...
        isfield(cfg,'micron_per_pix') && ~isempty(cfg.micron_per_pix);
    if use_um, scale = cfg.micron_per_pix; end
    xx = (1:width)*scale;
    yy = (1:height)*scale;

    out_file = fullfile(cfg.out_data_path, ...
        sprintf('%s_%s_kymograph_demo.mp4',cfg.data_name,cfg.channel_names{ch_idx}));
    writer = VideoWriter(out_file,'MPEG-4');
    writer.FrameRate = fieldOr(mp,'replay_fps',10);
    writer.Quality = 100;
    open(writer);
    fig = figure('Color','w','Units','pixels', ...
        'Position',[100 100 1600 650], 'Visible','on', ...
        'Name',sprintf('Merged movie + %s kymograph',cfg.channel_names{ch_idx}));
    cleanup = onCleanup(@() finishVideo(writer, fig));

    % Fixed axes positions, fixed image limits, fixed panel geometry.
    ax_movie = axes('Parent',fig,'Units','normalized','Position',[0.065 0.17 0.43 0.70]);
    ax_kymo = axes('Parent',fig,'Units','normalized','Position',[0.57 0.17 0.36 0.70]);
    % A shared title in a fixed rectangle does not resize either axes.
    shared_title = annotation(fig,'textbox',[0.08 0.915 0.84 0.065], ...
        'String','', 'EdgeColor','none', ...
        'HorizontalAlignment','center', 'VerticalAlignment','middle', ...
        'FontName',font_name, 'FontSize',font_sz, 'FontWeight',font_wt, ...
        'Interpreter','none');
    set([ax_movie ax_kymo],'FontName',font_name,'FontSize',font_sz, ...
        'FontWeight',font_wt,'LineWidth',fieldOr(cfg.plot,'line_width',1.5));

    kdata = Kymograph(isfinite(Kymograph));
    if isempty(kdata), klim = [0 1];
    else, klim = [min(kdata),max(kdata)]; end
    if klim(1)==klim(2), klim(2)=klim(1)+1; end
    partial = zeros(size(Kymograph));

    for f = first_frame:last_frame
        row = f-first_frame+1;
        r = contrastSmart(ch1(:,:,f),red_limits);
        g = contrastSmart(ch2(:,:,f),green_limits);
        
        % % % Show red/green color:
        % % if ch_idx == 1
        % %     rgb = cat(3,r,zeros(size(r)),zeros(size(r)));
        % % else
        % %     rgb = cat(3,zeros(size(g)),g,zeros(size(g)));
        % % end
        % % % Show gray scale: 
        if ch_idx == 1
            rgb = cat(3,r,r,r);  % Channel 1: Grayscale
        else
            rgb = cat(3,g,g,g);  % Channel 2: Grayscale
        end

        % LEFT: replicate showDiagnosticMovie merged display and LOI.
        cla(ax_movie);
        image(ax_movie, xx, yy, rgb);
        set(ax_movie,'YDir','reverse');
        xlim(ax_movie,[xx(1) xx(end)]);
        ylim(ax_movie,[yy(1) yy(end)]);
        axis(ax_movie,'image');
        % Hold manual limits after axis image so long LOIs cannot expand canvas.
        set(ax_movie,'XLimMode','manual','YLimMode','manual');
        hold(ax_movie,'on');
        s1 = reshape(pos_spots(1,:,f),1,[]);
        s2 = reshape(pos_spots(2,:,f),1,[]);
        s3 = [NaN NaN];
        if size(pos_spots,1)>=3, s3=reshape(pos_spots(3,:,f),1,[]); end
        if all(isfinite(s1)) && all(isfinite(s2))
            len = norm(s2-s1); if len==0, len=1e-5; end
            if has_prot
                e1 = s2+(s1-s2)*(max_len21/len)+(s1-s2)/len*extension;
                valid3 = all(isfinite(s3));
                if valid3
                    len3 = norm(s3-s2); if len3==0, len3=1e-5; end
                    e3 = s2+(s3-s2)*(max_len23/len3)+(s3-s2)/len3*extension;
                else
                    e3 = s2+(s2-s1)/len*(max_len23+extension);
                end
                plot(ax_movie,[e1(1) s2(1)]*scale,[e1(2) s2(2)]*scale, ...
                    '-','Color',spb_color,'LineWidth',line_w);
                color3 = spb_color;
                if valid3, color3=prot_color; end
                plot(ax_movie,[s2(1) e3(1)]*scale,[s2(2) e3(2)]*scale, ...
                    '-','Color',color3,'LineWidth',line_w);
            else
                direction = (s2-s1)/len;
                e1=s1-direction*extension;
                e2=s1+direction*(max_len21+extension);
                plot(ax_movie,[e1(1) e2(1)]*scale,[e1(2) e2(2)]*scale, ...
                    '-','Color',spb_color,'LineWidth',line_w);
            end
        end
        if ~isempty(spot_marker) && ~strcmpi(spot_marker,'none') && spot_size>0
            spots = [s1; s2; s3];
            for s = 1:min(3,size(spot_colors,1))
                if all(isfinite(spots(s,:)))
                    plot(ax_movie,spots(s,1)*scale,spots(s,2)*scale,spot_marker, ...
                        'Color',spot_colors(s,:),'MarkerSize',spot_size,'LineWidth',2);
                end
            end
        end
        hold(ax_movie,'off');
        if fieldOr(mp,'show_title',true)
            shared_title.String = sprintf('Cell: %s | %s | Frame %d', ...
                cfg.data_name,cfg.channel_names{ch_idx},f);
        else
            shared_title.String = '';
        end
        if fieldOr(mp,'show_axis_labels',true)
            unit='(pixels)'; if use_um, unit='(\mum)'; end
            xlabel(ax_movie,['Distance ' unit],'FontSize',label_sz,'FontName',font_name);
            ylabel(ax_movie,['Distance ' unit],'FontSize',label_sz,'FontName',font_name);
        end
        if ~fieldOr(mp,'show_axis_ticks',true)
            set(ax_movie,'XTick',[],'YTick',[]);
        else
            fixedTicks(ax_movie,'x',xx,fieldOr(mp,'x_tick_step',[]));
            fixedTicks(ax_movie,'y',yy,fieldOr(mp,'y_tick_step',[]));
        end
        set(ax_movie,'FontName',font_name,'FontSize',font_sz,'FontWeight',font_wt);
        xtickangle(ax_movie,0);
        ytickangle(ax_movie,0);
        xlim(ax_movie,[xx(1) xx(end)]); ylim(ax_movie,[yy(1) yy(end)]);

        % RIGHT: grow the advanced kymograph, with optional time indicator.
        partial(row,:) = Kymograph(row,:);
        cla(ax_kymo);
        imagesc(ax_kymo,x_axis,t_axis,partial,klim);
        colormap(ax_kymo,gray(256));
        set(ax_kymo,'YDir','reverse','Color','k');
        xlim(ax_kymo,[x_axis(1) x_axis(end)]);
        ylim(ax_kymo,[t_axis(1) t_axis(end)]);
        if show_current_time_line
            hold(ax_kymo,'on');
            plot(ax_kymo,[x_axis(1) x_axis(end)],[t_axis(row) t_axis(row)], ...
                '-','Color',spb_color,'LineWidth',line_w);
            hold(ax_kymo,'off');
        end
        % RIGHT demo uses MOVIE typography, not cfg.plot.kymo fonts/labels.
        % cfg.plot.kymo controls only the separately exported static figures.
        set(ax_kymo,'FontSize',font_sz,'FontName',font_name, ...
            'FontWeight',font_wt,'LineWidth',fieldOr(cfg.plot,'line_width',1.5));
        if fieldOr(mp,'show_axis_ticks',true)
            fixedTicks(ax_kymo,'x',x_axis,fieldOr(kp,'x_tick_step',[]));
            fixedTicks(ax_kymo,'y',t_axis,fieldOr(kp,'y_tick_step',[]));
        else
            set(ax_kymo,'XTick',[],'YTick',[]);
        end
        xtickangle(ax_kymo,0);
        ytickangle(ax_kymo,0);
        if fieldOr(mp,'show_axis_labels',true)
            xunit=fieldOr(kp,'x_unit','um');
            tunit=fieldOr(kp,'t_unit','min');
            xl='Distance (\mum)';
            if strcmpi(xunit,'pixel'), xl='Distance (pixels)'; end
            yl='Time (min)';
            if strcmpi(tunit,'s'), yl='Time (s)'; end
            if strcmpi(tunit,'frame'), yl='Frame'; end
            xlabel(ax_kymo,xl,'FontSize',label_sz,'FontName',font_name);
            ylabel(ax_kymo,yl,'FontSize',label_sz,'FontName',font_name);
        else
            xlabel(ax_kymo,'');
            ylabel(ax_kymo,'');
        end
        drawnow;
        writeVideo(writer,getframe(fig));
    end
    clear cleanup;
    fprintf('Channel %d kymograph demo saved: %s\n',ch_idx,out_file);
end

function v = fieldOr(s,k,default)
    v=default;
    if isstruct(s) && isfield(s,k) && ~isempty(s.(k)),v=s.(k);end
end

function movie = toProjection(raw)
    if ndims(raw)==4
        movie=squeeze(max(raw,[],3));
    else
        movie=raw;
    end
end

function [r,g] = movieContrast(cfg)
    limits=fieldOr(cfg.plot,'movie_contrast',struct());
    if isstruct(limits)
        r=fieldOr(limits,'red',[200 400]);
        g=fieldOr(limits,'green',[200 450]);
    elseif isnumeric(limits) && isequal(size(limits),[2 2])
        r=limits(1,:);g=limits(2,:);
    else
        r=[200 400];g=[200 450];
    end
end

function img = contrastSmart(img,limits)
    d=double(img);
    bad=isnan(d);d(bad)=0;
    if max(limits)<=1
        img=imadjust(rescale(d),limits,[]);
    else
        img=max(0,min(1,(d-limits(1))/(limits(2)-limits(1))));
    end
    img(bad)=0;
end

function fixedTicks(ax,dim,values,step)
    if ~isempty(step) && step>0
        ticks=ceil(values(1)/step)*step:step:values(end);
        if strcmp(dim,'x'),xticks(ax,ticks);else,yticks(ax,ticks);end
    end
end

function s=resolveLabel(candidate,automatic)
    s=candidate;
    if strcmpi(strtrim(char(candidate)),'auto'),s=automatic;end
end

function finishVideo(writer,fig)
    try close(writer);catch,end
    if isgraphics(fig),close(fig);end
end

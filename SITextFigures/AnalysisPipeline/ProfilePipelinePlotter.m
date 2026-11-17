%% ANGLE_PIPELINE
% One-file version of the angle_finder post-processing tools.
% Run this whole script (F5) to load your results, fix the intersection
% bug, optionally refit near flattened tips, compute theta_c (the flank
% angle from HORIZONTAL at the crease, as in the paper's Fig. 1) for each
% side, estimate peak height and total profile arclength, print a summary
% table, and save the values to an Excel workbook.
% Plots are off by default (make_plots = false). All functions are LOCAL
% FUNCTIONS at the bottom of this same file.
%
% With make_plots = true, step_through_peaks draws one peak at a time in a
% single figure, clearing between peaks. Set a breakpoint on the line
% marked BREAKPOINT inside step_through_peaks to step through them.
%
% Edit the settings below, then run the whole file (F5 / Run, NOT Run Section).
clear all
matfile = 'thirtymicronpeaks_angles2.mat';   % <-- your saved results file
varname = 'peak_angles_info';                % <-- struct variable name inside it
gap_tol = 0.15;   % mm: flag a peak if its left/right fits disagree by more than this at the join
level_tol = 0.5;  % deg: rotate a peak so its baseline is horizontal if the line joining its left and
                  %      right ends is tilted by more than this (Inf = never rotate)
end_frac  = 0.10; % fraction of each profile, from its outer end, used to locate the baseline
end_slope_tol = 5;  % deg: flag the baseline (and so the height) as uncertain if a crop end still slopes more than this
apex_tol  = 0.10; % mm: flag a peak if its fit-tip height and data-apex height differ by more than this
arc_smooth = 5;   % points: moving-mean window used before measuring the data arclength (1 = no smoothing)
profile_scale = 0.5; % uniform scale (x AND y, all mm quantities) applied AFTER the measurements: profile, fits, tip, baseline and
                     % heights shrink together, so every angle (theta_c, tip angle, tilt) is unchanged and h/(1-cos(theta))
                     % scales by exactly this factor. Arclength scales by it too. (Same as running angle_finder with
                     % ppmmx and ppmmy divided by this factor.)

make_plots = false;                         % <-- true = also step through every peak in the peak viewer
xlsx_file  = 'peak_results2.xlsx';            % <-- output workbook
profiles_csv = 'peak_profiles.csv';           % <-- every profile point, tagged with its peak number ('' = skip the CSV)
mat_dir      = 'peak_profiles_mat';           % <-- folder for one .mat file per peak (peak_001.mat, ...) ('' = skip)
center_export = true;   % <-- exported profiles centered: tip at x = 0, and the baseline line used for the height is y = 0
export_y_up   = false;  % <-- with center_export: true flips y so the peak points up (tip at +height); false keeps y down (tip at -height)

tip_win_frac = 0.10;    % half-width of the near-tip straight-line fit window, as a fraction of the profile's x-range

% ---- Pipeline showcase (one peak, step by step) ----
showcase          = true;   % <-- draw the step-by-step pipeline figure for one peak
showcase_peak_num = 6;      % <-- peak number to show; [] = pick it from a list when the script runs
showcase_separate = false;  % <-- false: one 2x2 figure; true: each stage in its own figure (handy for slides)
showcase_png      = 'pipeline_peak_%03d.png';  % <-- saved image name ('' = don't save); separate figures get _a.._d
showcase_center   = true;   % <-- tip at x = 0, baseline at y = 0, y up (= height above the baseline); false = raw image coordinates
showcase_panels   = 'bc';   % <-- stages to draw, any of 'abcd': a raw, b leveled + poly fits, c tip line fits, d result
showcase_overlay  = true;   % <-- draw the result (tip, height, theta_c arcs) on top of panel b, so d isn't needed
showcase_titles   = false;  % <-- false = no panel titles/subtitles (axis labels and legends stay)
showcase_letters  = true;   % <-- panel letters (a), (b), ... in the top-left corner of each panel

if ~exist(varname, 'var')
    S = load(matfile);
    if ~isfield(S, varname)
        error('Variable ''%s'' not found in %s.', varname, matfile);
    end
    peak_data = S.(varname);
else
    peak_data = eval(varname);
end
fprintf('Loaded %s: class = %s, size = %s\n', varname, class(peak_data), mat2str(size(peak_data)));

leveled = level_baseline(peak_data, 'TiltTol', level_tol, 'EndFrac', end_frac);
fixed   = fix_intersection(leveled);
refined = refine_peak_angle(fixed, 'AngleThreshold', 30, 'Degree', 1, 'WindowFrac', tip_win_frac);
withtc  = compute_theta_c(refined, 'Tolerance', 5);
withtc  = compute_height(withtc, 'EndSlopeTol', end_slope_tol);
withtc  = apply_scale(withtc, profile_scale);                  % uniform x/y scaling: angles unchanged, heights x scale
withtc  = compute_arclength(withtc, 'SmoothPts', arc_smooth);

% Same chain WITHOUT rotating (tilt is only measured), for the "before" values
orig_lv = level_baseline(peak_data, 'TiltTol', Inf, 'EndFrac', end_frac);
orig_fx = fix_intersection(orig_lv);
orig_rf = refine_peak_angle(orig_fx, 'AngleThreshold', 30, 'Degree', 1, 'WindowFrac', tip_win_frac);
orig_tc = compute_theta_c(orig_rf, 'Tolerance', 5);
orig_tc = compute_height(orig_tc, 'EndSlopeTol', end_slope_tol);
orig_tc = apply_scale(orig_tc, profile_scale);
orig_tc = compute_arclength(orig_tc, 'SmoothPts', arc_smooth);

tc_list   = collect_structs(withtc);
orig_list = collect_structs(orig_tc);
n = numel(tc_list);

% ---- Preallocate result columns ----
Peak = (1:n)';
[tilt_deg, dy_mm, height_tip_mm, height_apex_mm, theta_L_deg, theta_R_deg, sym_deg, diff_deg, ...
    angle_deg, angle_deg_global, gap_mm, one_over_1mcos, h_over_1mcos, ...
    pre_theta_L_deg, pre_theta_R_deg, arc_data_mm, arc_fit_mm] = deal(NaN(n,1));
leveled_flag = false(n,1);  asymmetric = false(n,1);  baseline_ok = false(n,1);
tip_method = repmat({''}, n, 1);  flag_text = repmat({'no angle'}, n, 1);

fprintf('\n%-6s %8s %9s %10s %10s %10s %10s %10s  %s\n', 'Peak', 'tilt', 'height', 'theta_L', 'theta_R', 'sym avg', 'L-R diff', 'arclen', 'flags');
for k = 1:n
    e = tc_list{k};
    if ~isstruct(e) || ~isfield(e, 'theta_c') || isnan(e.theta_c.left_deg) || isnan(e.theta_c.right_deg)
        fprintf('%-6d %8s %9s %10s %10s %10s %10s %10s  %s\n', k, '-', '-', '-', '-', '-', '-', '-', 'no angle');
        continue;
    end
    t  = e.theta_c;
    ti = e.tip_info;
    flags = {};
    o = orig_list{k};
    o_ok = isstruct(o) && isfield(o, 'theta_c') && ~isnan(o.theta_c.left_deg) && ~isnan(o.theta_c.right_deg);
    if o_ok
        pre_theta_L_deg(k) = o.theta_c.left_deg;
        pre_theta_R_deg(k) = o.theta_c.right_deg;
    end
    if e.level.applied
        if o_ok
            flags{end+1} = sprintf('leveled (pre-tilt %.1f/%.1f)', o.theta_c.left_deg, o.theta_c.right_deg); %#ok<SAGROW>
        else
            flags{end+1} = 'leveled'; %#ok<SAGROW>
        end
    end
    if ~e.height.baseline_ok
        flags{end+1} = 'crop ends not flat (baseline uncertain)'; %#ok<SAGROW>
    end
    if abs(e.height.height_tip_mm - e.height.height_apex_mm) > apex_tol * profile_scale
        flags{end+1} = sprintf('height: fit tip vs data apex differ by %.2f mm', ...
            e.height.height_tip_mm - e.height.height_apex_mm); %#ok<SAGROW>
    end
    if isfinite(e.height.height_tip_mm) && abs(e.level.dy_mm) > e.height.height_tip_mm
        flags{end+1} = sprintf('end-to-end offset %.2f mm exceeds height', abs(e.level.dy_mm)); %#ok<SAGROW>
    end
    if strcmp(ti.method, 'junction'), flags{end+1} = 'no crossing near join (junction used)'; end %#ok<SAGROW>
    if ~ti.slopes_opposite,           flags{end+1} = 'same-sign slopes (not peak-like)'; end     %#ok<SAGROW>
    if ti.gap_mm > gap_tol * profile_scale,           flags{end+1} = sprintf('fit gap %.2f mm', ti.gap_mm); end  %#ok<SAGROW>
    if t.asymmetric,                  flags{end+1} = 'asymmetric'; end                           %#ok<SAGROW>
    if isempty(flags), flagstr = 'ok'; else, flagstr = strjoin(flags, '; '); end

    % ---- store values ----
    tilt_deg(k) = e.level.tilt_deg;          dy_mm(k) = e.level.dy_mm;
    leveled_flag(k) = e.level.applied;       baseline_ok(k) = e.height.baseline_ok;
    height_tip_mm(k) = e.height.height_tip_mm;
    height_apex_mm(k) = e.height.height_apex_mm;
    theta_L_deg(k) = t.left_deg;  theta_R_deg(k) = t.right_deg;
    sym_deg(k) = t.sym_deg;       diff_deg(k) = t.diff_deg;   asymmetric(k) = t.asymmetric;
    angle_deg(k) = e.angle_deg;   angle_deg_global(k) = e.angle_deg_global;
    tip_method{k} = ti.method;    gap_mm(k) = ti.gap_mm;
    one_over_1mcos(k) = 1 / (1 - cosd(t.sym_deg));
    h_over_1mcos(k)   = e.height.height_tip_mm / (1 - cosd(t.sym_deg));
    arc_data_mm(k) = e.arclength.data_mm;
    arc_fit_mm(k)  = e.arclength.fit_mm;
    flag_text{k} = flagstr;

    fprintf('%-6d %8.2f %9.2f %10.2f %10.2f %10.2f %10.2f %10.2f  %s\n', k, e.level.tilt_deg, e.height.height_tip_mm, t.left_deg, t.right_deg, t.sym_deg, t.diff_deg, e.arclength.fit_mm, flagstr);
end
fprintf('\n');

% ---- Build tables ----
T_summary = table(Peak, leveled_flag, tilt_deg, dy_mm, height_tip_mm, height_apex_mm, baseline_ok, ...
    theta_L_deg, theta_R_deg, sym_deg, diff_deg, asymmetric, ...
    angle_deg, angle_deg_global, tip_method, gap_mm, one_over_1mcos, h_over_1mcos, ...
    arc_data_mm, arc_fit_mm, ...
    pre_theta_L_deg, pre_theta_R_deg, flag_text, ...
    'VariableNames', {'Peak','Leveled','Tilt_deg','EndToEndOffset_mm','Height_tip_mm','Height_apex_mm','BaselineOK', ...
    'ThetaC_L_deg','ThetaC_R_deg','ThetaC_sym_deg','ThetaC_LRdiff_deg','Asymmetric', ...
    'TipAngle_deg','TipAngle_global_deg','TipMethod','FitGap_mm','One_over_1mCos','H_over_1mCos', ...
    'Arclength_data_mm','Arclength_fit_mm', ...
    'PreLevel_ThetaC_L_deg','PreLevel_ThetaC_R_deg','Flags'});

% "Before leveling" values
[o_tilt, o_h, o_L, o_R, o_sym, o_diff] = deal(NaN(n,1));
for k = 1:n
    o = orig_list{k};
    if isstruct(o) && isfield(o, 'theta_c') && ~isnan(o.theta_c.left_deg)
        o_tilt(k) = o.level.tilt_deg;   o_h(k) = o.height.height_tip_mm;
        o_L(k) = o.theta_c.left_deg;    o_R(k) = o.theta_c.right_deg;
        o_sym(k) = o.theta_c.sym_deg;   o_diff(k) = o.theta_c.diff_deg;
    end
end
T_before = table(Peak, o_tilt, o_h, o_L, o_R, o_sym, o_diff, 'VariableNames', ...
    {'Peak','Tilt_deg','Height_tip_mm','ThetaC_L_deg','ThetaC_R_deg','ThetaC_sym_deg','ThetaC_LRdiff_deg'});

T_settings = table({'matfile';'varname';'gap_tol';'level_tol';'end_frac';'end_slope_tol';'apex_tol';'arc_smooth';'profile_scale'}, ...
    {matfile; varname; num2str(gap_tol); num2str(level_tol); num2str(end_frac); num2str(end_slope_tol); num2str(apex_tol); num2str(arc_smooth); num2str(profile_scale)}, ...
    'VariableNames', {'Setting','Value'});

% ---- Write workbook ----
out_file = xlsx_file;
try
    if isfile(out_file), delete(out_file); end   % avoid stale sheets from earlier runs
    writetable(T_summary, out_file, 'Sheet', 'Summary');
catch
    [~, nm, ext] = fileparts(xlsx_file);          % file probably open in Excel
    out_file = sprintf('%s_%s%s', nm, datestr(now, 'yyyymmdd_HHMMSS'), ext);
    warning('Could not write %s (open in Excel?). Writing %s instead.', xlsx_file, out_file);
    writetable(T_summary, out_file, 'Sheet', 'Summary');
end
writetable(T_before,   out_file, 'Sheet', 'Before_leveling');
writetable(T_settings, out_file, 'Sheet', 'Settings');

% ---- Export every profile, tagged with its peak number (same numbering as Summary.Peak) ----
% Final geometry: leveled, scaled by profile_scale, in mm. Long format: one row per point.
% With center_export each peak is shifted so its tip is at x = 0, and the baseline line that the
% height is measured from (horizontal for leveled peaks, the slightly tilted line otherwise) is
% subtracted so it becomes y = 0 (the tip then sits at -height). export_y_up flips y so the peak
% points up. The Tips sheet always stays in the original coordinates. Peaks with no tip/baseline
% can't be centered and are skipped.
pf_sides = {'left', 'right'};
pf_pts = {};  pf_fit = {};  pf_tip = {};  pf_skipped = [];
pf_ysign = 1;
if center_export && export_y_up, pf_ysign = -1; end
for pf_k = 1:n
    pf_e = tc_list{pf_k};
    if ~isstruct(pf_e) || ~isfield(pf_e, 'left') || ~isfield(pf_e, 'right'), continue; end
    if ~isempty(pf_e.intersection_pt_mm) && all(isfinite(pf_e.intersection_pt_mm))
        pf_tip{end+1} = table(pf_k, pf_e.intersection_pt_mm(1), pf_e.intersection_pt_mm(2), ...
            pf_e.height.baseline_y_mm, pf_e.height.height_tip_mm, ...
            'VariableNames', {'Peak', 'TipX_mm', 'TipY_mm', 'BaselineY_mm', 'Height_tip_mm'}); %#ok<SAGROW>
    end
    pf_dx = 0;  pf_base = @(xx) 0*xx;
    if center_export
        [pf_dx, ~, pf_can] = export_offsets(pf_e);
        if ~pf_can
            pf_skipped(end+1) = pf_k; %#ok<SAGROW>
            continue;
        end
        pf_base = @(xx) baseline_y_at(pf_e, xx);   % the baseline line used for the height
    end
    for pf_i = 1:2
        pf_h = pf_e.(pf_sides{pf_i});
        pf_x = pf_h.x_mm(:) - pf_dx;  pf_y = pf_ysign * (pf_h.y_mm(:) - pf_base(pf_h.x_mm(:)));
        pf_ok = isfinite(pf_x) & isfinite(pf_y);
        if any(pf_ok)
            pf_pts{end+1} = table(repmat(pf_k, nnz(pf_ok), 1), repmat(pf_sides(pf_i), nnz(pf_ok), 1), ...
                pf_x(pf_ok), pf_y(pf_ok), 'VariableNames', {'Peak', 'Side', 'x_mm', 'y_mm'}); %#ok<SAGROW>
        end
        pf_xf = pf_h.xfit_mm(:) - pf_dx;  pf_yf = pf_ysign * (pf_h.yfit_mm(:) - pf_base(pf_h.xfit_mm(:)));
        pf_okf = isfinite(pf_xf) & isfinite(pf_yf);
        if any(pf_okf)
            pf_fit{end+1} = table(repmat(pf_k, nnz(pf_okf), 1), repmat(pf_sides(pf_i), nnz(pf_okf), 1), ...
                pf_xf(pf_okf), pf_yf(pf_okf), 'VariableNames', {'Peak', 'Side', 'x_mm', 'y_mm'}); %#ok<SAGROW>
        end
    end
end
if ~isempty(pf_skipped)
    warning('Could not center (no tip/baseline), so not exported: peaks %s', mat2str(pf_skipped));
end
if ~isempty(pf_pts)
    T_profiles = vertcat(pf_pts{:});
    writetable(T_profiles, out_file, 'Sheet', 'Profiles');
    if ~isempty(profiles_csv)
        writetable(T_profiles, profiles_csv);
        fprintf('Saved %d profile points to %s\n', height(T_profiles), fullfile(pwd, profiles_csv));
    end
end
if ~isempty(pf_fit)
    writetable(vertcat(pf_fit{:}), out_file, 'Sheet', 'Fit_curves');
end
if ~isempty(pf_tip)
    writetable(vertcat(pf_tip{:}), out_file, 'Sheet', 'Tips');
end

% ---- One .mat file per peak: just the stitched profile (left + right halves joined) ----
% Same geometry/centering as above. Each file contains only x_mm and y_mm (column vectors,
% ordered left to right); the peak number is in the file name.
if ~isempty(mat_dir)
    if ~isfolder(mat_dir), mkdir(mat_dir); end
    pf_nsaved = 0;
    for pf_k = 1:n
        pf_e = tc_list{pf_k};
        if ~isstruct(pf_e) || ~isfield(pf_e, 'left') || ~isfield(pf_e, 'right'), continue; end
        pf_dx = 0;  pf_base = @(xx) 0*xx;
        if center_export
            [pf_dx, ~, pf_can] = export_offsets(pf_e);
            if ~pf_can, continue; end
            pf_base = @(xx) baseline_y_at(pf_e, xx);
        end
        pf_xo = [pf_e.left.x_mm(:);  pf_e.right.x_mm(:)];
        x_mm = pf_xo - pf_dx;
        y_mm = pf_ysign * ([pf_e.left.y_mm(:);  pf_e.right.y_mm(:)] - pf_base(pf_xo));
        pf_ok = isfinite(x_mm) & isfinite(y_mm);
        x_mm = x_mm(pf_ok);  y_mm = y_mm(pf_ok);
        if isempty(x_mm), continue; end
        [x_mm, pf_ord] = sort(x_mm);   % left half then right half, in x order
        y_mm = y_mm(pf_ord);
        save(fullfile(mat_dir, sprintf('peak_%03d.mat', pf_k)), 'x_mm', 'y_mm');
        pf_nsaved = pf_nsaved + 1;
    end
    fprintf('Saved %d per-peak .mat files to %s\n', pf_nsaved, fullfile(pwd, mat_dir));
end
fprintf('Saved results to %s\n', fullfile(pwd, out_file));

% ---- Pipeline showcase for one chosen peak ----
if showcase
    sc_k = showcase_peak_num;
    if isempty(sc_k)
        sc_k = choose_peak(T_summary);
    end
    if ~isempty(sc_k)
        showcase_pipeline(peak_data, withtc, sc_k, end_frac, tip_win_frac, ...
            profile_scale, showcase_png, showcase_separate, showcase_center, showcase_panels, ...
            showcase_overlay, showcase_titles, showcase_letters);
    end
end

% ---- Plots (suppressed unless make_plots = true) ----
if make_plots
    step_through_peaks(orig_tc, withtc);   % one peak at a time, clears between each
    % plot_fit_panels(orig_tc, withtc);    % (old all-at-once version)
    % plot_profiles(withtc);               % (full 3-column version, with the pixel-space profiles too)
end


%% ==================================================================
%  Local functions below -- callable from code above and from each
%  other, but not from the Command Window or other files.
%  ==================================================================

% --------------------------- choose_peak --------------------------
function k = choose_peak(T)
% CHOOSE_PEAK  Let the user pick one peak from the summary table. Uses a
% list dialog when a display is available, otherwise asks in the Command
% Window. Returns [] if the user cancels.
k = [];
strs = cell(height(T), 1);
for i = 1:height(T)
    if isnan(T.ThetaC_sym_deg(i))
        strs{i} = sprintf('Peak %d:  no angle', T.Peak(i));
    else
        strs{i} = sprintf('Peak %d:  theta_c = %.1f deg,  h = %.3f mm,  %s', ...
            T.Peak(i), T.ThetaC_sym_deg(i), T.Height_tip_mm(i), T.Flags{i});
    end
end
try
    [idx, ok] = listdlg('ListString', strs, 'SelectionMode', 'single', ...
        'Name', 'Pipeline showcase', 'PromptString', 'Choose a peak to showcase:', ...
        'ListSize', [560 320]);
    if ok, k = T.Peak(idx); end
catch
    fprintf('%s\n', strs{:});
    k = input('Peak number to showcase (Enter to skip): ');
end
end


% ------------------------ showcase_pipeline -----------------------
function showcase_pipeline(raw_info, final_info, k, end_frac, win_frac, scale, png_file, separate, center, panels, overlay, titles, letters)
% SHOWCASE_PIPELINE  Step-by-step figure for one peak (any subset of these):
%   (a) raw edge profile, as saved by angle_finder
%   (b) leveled + scaled profile with the global polynomial fits, the
%       baseline and the end regions used to find it
%   (c) zoom on the tip: the straight-line fits over the near-tip window
%       (+/- win_frac of the profile's x-range) and their intersection
%   (d) final result: theta_c arcs and height (the pipeline's own plot)
% With center = true every panel is shifted so the tip is at x = 0 and the
% baseline at y = 0, with y pointing up (y = height above the baseline).
% This is a pure translation + flip, so no angle changes. The raw panel
% keeps its original tilt: it is centered on the tip, with y = 0 at the
% (tilted) baseline directly below it.
if nargin < 8, separate = false; end
if nargin < 9, center = true; end
if nargin < 10 || isempty(panels), panels = 'abcd'; end
if nargin < 11, overlay = false; end   % true: tip, height and theta_c arcs drawn on panel (b)
if nargin < 12, titles = true; end     % false: no panel titles
if nargin < 13, letters = false; end   % true: (a), (b), ... in each panel's corner
% panels: which stages to draw, e.g. 'bcd'. They are laid out in one row
% (2x2 for all four) and lettered (a), (b), ... in the order drawn.
panels = intersect('abcd', lower(panels));   % sorted, no repeats
npan = numel(panels);

raw_items = collect_structs(raw_info);
fin_items = collect_structs(final_info);
if k < 1 || k > numel(fin_items) || ~isstruct(fin_items{k}) || ...
        ~isfield(fin_items{k}, 'left') || ~isfield(fin_items{k}, 'right')
    warning('showcase_pipeline: peak %d has no data.', k);
    return;
end
s = fin_items{k};
r = ensure_fields(raw_items{k});

s0 = s;   % uncentered copy (for the tilt text)
ydir = 'reverse';  xlab = '$x$ (mm)';  ylab = '$y$ (mm, image rows)';
xlab_raw = '$x$ (mm, as saved)';  ylab_raw = '$y$ (mm, as saved, image rows)';
rb = [];  % raw (tilted) baseline for panel (a): [x1 x2; y1 y2]
if center
    [sc, okc] = center_peak(s);
    [rc, rb, okr] = center_raw(r, s, scale);
    if okc && okr
        s = sc;  r = rc;  ydir = 'normal';
        xlab = '$x$ (mm)';  ylab = '$y$ (mm)';
        xlab_raw = '$x$ (mm)';  ylab_raw = '$y$ (mm)';
    else
        warning('showcase_pipeline: peak %d has no tip/baseline, so it is shown uncentered.', k);
        rb = [];
    end
end

cL = [0 0.35 0.65];  cR = [0.75 0.30 0.05];  grey = [0.65 0.65 0.65];
ttl_main = sprintf('Angle-extraction pipeline: peak %d', k);
figs = gobjects(0);
tlo = [];
if ~separate
    if npan == 4
        nr = 2;  nc = 2;  pos = [0.05 0.05 0.9 0.85];
    else
        nr = 1;  nc = npan;  pos = [0.03 0.2 0.94 0.55];
        if any(panels == 'b'), nc = npan + 1; end   % the full profile (b) gets a double-width tile
    end
    figs(1) = figure('Name', ttl_main, 'NumberTitle', 'off', 'Color', 'w', ...
        'Units', 'normalized', 'Position', pos);
    tlo = tiledlayout(figs(1), nr, nc, 'TileSpacing', 'compact', 'Padding', 'compact');
    if titles, title(tlo, ttl_main, 'FontWeight', 'bold'); end
end

[xl, yl] = sorted_pts(s.left.x_mm,  s.left.y_mm);
[xr, yr] = sorted_pts(s.right.x_mm, s.right.y_mm);
if isempty(xl) || isempty(xr)
    warning('showcase_pipeline: peak %d has no edge points after processing.', k);
    return;
end
lab = @(c) sprintf('(%c)', 'a' + find(panels == c) - 1);   % panel letter in the order drawn

% near-tip line fits and the zoom region of panel (c), worked out up front so
% panel (b) can outline the same region
lf = tip_line_fits(s, win_frac);
zx = [];  zy = [];
if lf.ok
    xc = lf.center;  w = lf.win;
    zx = [min(xc - 1.6*w, lf.xt - 0.3*w), max(xc + 1.6*w, lf.xt + 0.3*w)];
    inzL = xl >= zx(1) & xl <= zx(2);
    inzR = xr >= zx(1) & xr <= zx(2);
    yz = [yl(inzL); yr(inzR); lf.yt];
    pad = 0.15 * max(max(yz) - min(yz), eps);
    zy = [min(yz) - pad, max(yz) + pad];
end

% ---------------- (a) raw profile ----------------
if any(panels == 'a')
[ax, figs] = showcase_axes(tlo, separate, figs, sprintf('%s (a)', ttl_main));
hold(ax, 'on');
plot(ax, r.left.x_mm,  r.left.y_mm,  '.', 'Color', cL, 'MarkerSize', 6, 'DisplayName', 'Left edge');
plot(ax, r.right.x_mm, r.right.y_mm, '.', 'Color', cR, 'MarkerSize', 6, 'DisplayName', 'Right edge');
if ~isempty(rb)
    plot(ax, rb(1,:), rb(2,:), 'k:', 'LineWidth', 1.2, 'DisplayName', 'Baseline (as saved)');
end
set(ax, 'YDir', ydir);  axis(ax, 'equal');
latex_legend(ax, 'Location', 'best');
style_axes(ax, xlab_raw, ylab_raw);
if letters, panel_letter(ax, lab('a')); end
if titles
    title(ax, {[lab('a') ' Raw edge profile'], ...
        sprintf('%d left + %d right points, before leveling and scaling', ...
        nnz(isfinite(r.left.y_mm)), nnz(isfinite(r.right.y_mm)))});
end
hold(ax, 'off');
end

% ---------------- (b) leveled profile + polynomial fits ----------------
if any(panels == 'b')
bspan = 1;
if ~separate && npan < 4, bspan = 2; end
[ax, figs] = showcase_axes(tlo, separate, figs, sprintf('%s (b)', ttl_main), bspan);
hold(ax, 'on');
plot(ax, xl, yl, '.', 'Color', 0.5*cL + 0.5, 'MarkerSize', 5, 'DisplayName', 'Profilometry data');
plot(ax, xr, yr, '.', 'Color', 0.5*cR + 0.5, 'MarkerSize', 5, 'HandleVisibility', 'off');
plot(ax, s.left.xfit_mm,  s.left.yfit_mm,  '-', 'Color', cL, 'LineWidth', 2, 'HandleVisibility', 'off');
plot(ax, s.right.xfit_mm, s.right.yfit_mm, '-', 'Color', cR, 'LineWidth', 2, 'HandleVisibility', 'off');
xx = [min(xl) max(xr)];
yy = baseline_y_at(s, xx);
if all(isfinite(yy))
    plot(ax, xx, yy, 'k:', 'LineWidth', 1.2, 'HandleVisibility', 'off');
end
% legend: the data entry is the plotted points themselves (above); a neutral stand-in for the fits
plot(ax, NaN, NaN, '-', 'Color', [0.2 0.2 0.2], 'LineWidth', 2, 'DisplayName', 'Polynomial fit');
ylow = 0;
if overlay
    ylow = draw_result_overlay(ax, s);
end
if any(panels == 'c') && ~isempty(zx)   % outline the region shown zoomed in panel (c)
    plot(ax, zx([1 2 2 1 1]), zy([1 1 2 2 1]), '-', 'Color', [0.35 0.35 0.35], 'LineWidth', 0.8, ...
        'HandleVisibility', 'off');
end
set(ax, 'YDir', ydir);  axis(ax, 'equal');
% limits hugging the profile (true aspect ratio, so a flat profile is a wide strip, not a mostly empty box)
bx = [min(xl) max(xr)];  byl = [min([yl; yr; 0; ylow]) max([yl; yr; 0])];
bpad = 0.04 * (bx(2) - bx(1));
xlim(ax, bx + [-bpad bpad]);  ylim(ax, byl + [-bpad bpad]);
latex_legend(ax, 'Location', 'southoutside', 'Orientation', 'horizontal', 'Box', 'off');
style_axes(ax, xlab, ylab);
if letters, panel_letter(ax, lab('b')); end
if s0.level.applied
    lvl = sprintf('rotated by %.2f%s to level the baseline', s0.level.tilt_deg, char(176));
else
    lvl = sprintf('baseline tilt %.2f%s (not rotated)', s0.level.tilt_deg, char(176));
end
if scale ~= 1
    lvl = sprintf('%s; scaled x%.3g', lvl, scale);
end
if titles, title(ax, {[lab('b') ' Leveled profile + global polynomial fits'], lvl}); end
hold(ax, 'off');
end

% ---------------- (c) straight-line fits near the tip ----------------
if any(panels == 'c')
[ax, figs] = showcase_axes(tlo, separate, figs, sprintf('%s (c)', ttl_main));
hold(ax, 'on');
if ~lf.ok
    text(ax, 0.5, 0.5, 'near-tip line fits not available', 'Units', 'normalized', ...
        'HorizontalAlignment', 'center');
    axis(ax, 'off');
else
    % context: all nearby points (faded) and the global fits (thin)
    plot(ax, xl(inzL), yl(inzL), '.', 'Color', grey, 'MarkerSize', 6, 'DisplayName', 'Profilometry data');
    plot(ax, xr(inzR), yr(inzR), '.', 'Color', grey, 'MarkerSize', 6, 'HandleVisibility', 'off');
    xg = linspace(zx(1), zx(2), 200);
    plot(ax, xg(xg <= max(xl)), polyval(s.p_left,  xg(xg <= max(xl))), '-', 'Color', 0.4*cL + 0.6, ...
        'LineWidth', 1, 'HandleVisibility', 'off');
    plot(ax, xg(xg >= min(xr)), polyval(s.p_right, xg(xg >= min(xr))), '-', 'Color', 0.4*cR + 0.6, ...
        'LineWidth', 1, 'HandleVisibility', 'off');
    % points actually used for the line fits
    plot(ax, lf.xL, lf.yL, 'o', 'Color', cL, 'MarkerFaceColor', cL, 'MarkerSize', 4, 'HandleVisibility', 'off');
    plot(ax, lf.xR, lf.yR, 'o', 'Color', cR, 'MarkerFaceColor', cR, 'MarkerSize', 4, 'HandleVisibility', 'off');
    % line fits, extended across the zoom so the crossing is visible
    plot(ax, xg, polyval(lf.pL, xg), '--', 'Color', cL, 'LineWidth', 1.8, 'HandleVisibility', 'off');
    plot(ax, xg, polyval(lf.pR, xg), '--', 'Color', cR, 'LineWidth', 1.8, 'HandleVisibility', 'off');
    % edges of the fit window
    plot(ax, (xc - w)*[1 1], zy, ':', 'Color', [0.3 0.3 0.3], 'HandleVisibility', 'off');
    plot(ax, (xc + w)*[1 1], zy, ':', 'Color', [0.3 0.3 0.3], 'HandleVisibility', 'off');
    % legend: neutral-coloured stand-ins (left/right share each entry)
    gk = [0.25 0.25 0.25];
    plot(ax, NaN, NaN, '-', 'Color', [0.6 0.6 0.6], 'LineWidth', 1, 'DisplayName', 'Polynomial fit');
    plot(ax, NaN, NaN, '--', 'Color', gk, 'LineWidth', 1.8, 'DisplayName', 'Linear fit');
    set(ax, 'YDir', ydir);
    xlim(ax, zx);  ylim(ax, zy);   % not equal-aspect: a shallow tip would be a thin strip
    latex_legend(ax, 'Location', 'best');
    style_axes(ax, xlab, ylab);
    if letters, panel_letter(ax, lab('c')); end
    wpct = 100 * w / lf.total_range;
    l2 = sprintf('window = tip %s %.3g mm (%.0f%% of profile width each side)', char(177), w, wpct);
    if lf.used
        l3 = 'used by the pipeline for theta_c';
    else
        l3 = 'NOT used: tip angle > 30 deg, so theta_c comes from the global fit';
    end
    if titles, title(ax, {[lab('c') ' Straight-line fits near the tip'], l2, l3}); end
end
hold(ax, 'off');
end

% ---------------- (d) final result ----------------
if any(panels == 'd')
[ax, figs] = showcase_axes(tlo, separate, figs, sprintf('%s (d)', ttl_main));
plot_mm_fits(ax, s, [lab('d') ' Result: theta_c and height']);
if ~titles, title(ax, ''); end
set(ax, 'YDir', ydir);   % plot_mm_fits assumes image rows; undo that when centered
style_axes(ax, xlab, ylab);
lg = get(ax, 'Legend');
if ~isempty(lg), set(lg, 'Interpreter', 'latex', 'FontSize', 11); end
if letters, panel_letter(ax, lab('d')); end
end

% ---------------- save ----------------
if ~isempty(png_file)
    if any(png_file == '%')
        png_file = sprintf(png_file, k);   % fill in the peak number
    end
    try
        if numel(figs) == 1
            exportgraphics(figs(1), png_file, 'Resolution', 200);
            fprintf('Saved showcase figure to %s\n', fullfile(pwd, png_file));
        else
            [d, nm, ext] = fileparts(png_file);
            for i = 1:numel(figs)
                fn = fullfile(d, sprintf('%s_%s%s', nm, panels(i), ext));
                exportgraphics(figs(i), fn, 'Resolution', 200);
            end
            fprintf('Saved %d showcase figures to %s\n', numel(figs), fullfile(pwd, d));
        end
    catch err
        warning('showcase_pipeline: could not save the figure (%s).', err.message);
    end
end

end


function style_axes(ax, xlab, ylab)
% Common look for the showcase panels: LaTeX tick labels and axis labels,
% no grid, thin box.
set(ax, 'TickLabelInterpreter', 'latex', 'FontSize', 11, 'LineWidth', 0.75, ...
    'Box', 'on', 'XGrid', 'off', 'YGrid', 'off');
xlabel(ax, xlab, 'Interpreter', 'latex', 'FontSize', 13);
ylabel(ax, ylab, 'Interpreter', 'latex', 'FontSize', 13);
end


function latex_legend(ax, varargin)
% Legend from the DisplayNames, rendered with the LaTeX interpreter.
legend(ax, varargin{:}, 'Interpreter', 'latex', 'FontSize', 11);
end


function panel_letter(ax, str)
% Panel letter in the top-left corner, inside the axes. Placed in data
% units (after the limits are set), so it stays inside the plot box even
% when axis equal shrinks that box.
xl = xlim(ax);  yl = ylim(ax);
x = xl(1) + 0.012 * diff(xl);
if strcmp(get(ax, 'YDir'), 'reverse')
    y = yl(1) + 0.04 * diff(yl);   % top of a reversed axis is the low limit
else
    y = yl(2) - 0.04 * diff(yl);
end
text(ax, x, y, str, 'Interpreter', 'latex', 'FontSize', 14, ...
    'HorizontalAlignment', 'left', 'VerticalAlignment', 'top', 'Clipping', 'off');
end


function ylow = draw_result_overlay(ax, s)
% The result on top of the (centered) profile panel, as symbols only:
%   delta  : height, tip down to the baseline
%   lambda : width, between the two feet (where each fit comes back down to
%            within 2% of delta of the baseline), drawn just below it
%   theta_L, theta_R : arcs at the tip
% Returns the lowest y used, so the caller can keep it inside the axes.
ylow = 0;
if isempty(s.intersection_pt_mm) || any(~isfinite(s.intersection_pt_mm)), return; end
xt = s.intersection_pt_mm(1);
yt = s.intersection_pt_mm(2);
by = baseline_y_at(s, xt);
if ~isfinite(by), return; end
delta = abs(yt - by);
dcol = [0.1 0.5 0.1];
tk = 0.06 * delta;   % half-length of the end ticks

% delta: vertical dimension line from the baseline to the tip
plot(ax, [xt xt], [by yt], '-', 'Color', dcol, 'LineWidth', 1.5, 'HandleVisibility', 'off');
plot(ax, xt + [-1 1]*tk, [by by], '-', 'Color', dcol, 'LineWidth', 1.5, 'HandleVisibility', 'off');
text(ax, xt + 2*tk, (yt + by)/2, '$H$', 'Color', dcol, 'FontSize', 16, ...
    'Interpreter', 'latex', 'VerticalAlignment', 'middle');

% lambda: feet of the blister on the fit curves (centered frame: y = height above baseline)
thr = 0.02 * delta;
xfL = foot_x(s.left.xfit_mm,  s.left.yfit_mm  - baseline_y_at(s, s.left.xfit_mm),  xt, thr, -1);
xfR = foot_x(s.right.xfit_mm, s.right.yfit_mm - baseline_y_at(s, s.right.xfit_mm), xt, thr, +1);
if isfinite(xfL) && isfinite(xfR)
    lcol = [0.3 0.3 0.3];
    yd = by - 0.35 * delta;   % dimension line just below the baseline
    plot(ax, [xfL xfL], [by yd - tk], ':', 'Color', lcol, 'HandleVisibility', 'off');
    plot(ax, [xfR xfR], [by yd - tk], ':', 'Color', lcol, 'HandleVisibility', 'off');
    plot(ax, [xfL xfR], [yd yd], '-', 'Color', lcol, 'LineWidth', 1.5, 'HandleVisibility', 'off');
    plot(ax, xfL, yd, '<', 'Color', lcol, 'MarkerFaceColor', lcol, 'MarkerSize', 5, 'HandleVisibility', 'off');
    plot(ax, xfR, yd, '>', 'Color', lcol, 'MarkerFaceColor', lcol, 'MarkerSize', 5, 'HandleVisibility', 'off');
    text(ax, (xfL + xfR)/2, yd, '$W$', 'Color', lcol, 'FontSize', 16, 'Interpreter', 'latex', ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'top');
    ylow = yd - 0.35 * delta;   % room for the lambda label
end

% theta_L / theta_R arcs, labelled by name instead of value
draw_theta_c_arcs(ax, s, {'$\theta_L$', '$\theta_R$'});
end


function xf = foot_x(xf_all, h_all, xt, thr, side)
% x of the blister foot on one side: moving outward from the tip along the
% fit, the first point whose height above the baseline is <= thr. Falls
% back to the outermost fit point if the fit never gets that low.
xf = NaN;
x = xf_all(:);  h = h_all(:);
ok = isfinite(x) & isfinite(h);
x = x(ok);  h = h(ok);
if isempty(x), return; end
if side < 0
    [x, o] = sort(x, 'descend');   % tip -> outer (left) end
else
    [x, o] = sort(x, 'ascend');    % tip -> outer (right) end
end
h = h(o);
keep = side * (x - xt) >= 0;
x = x(keep);  h = h(keep);
if isempty(x), return; end
i = find(abs(h) <= thr, 1, 'first');
if isempty(i), i = numel(x); end
xf = x(i);
end

function [c, ok] = center_peak(s)
% CENTER_PEAK  Copy of a processed peak shifted so the tip is at x = 0 and
% the baseline (at the tip) is at y = 0, with y flipped to point up:
%     x' = x - x_tip,    y' = y_base(x_tip) - y
% Every coordinate, fit curve and polynomial is transformed the same way,
% so slopes only change sign and every angle is unchanged.
c = s;  ok = false;
if isempty(s.intersection_pt_mm) || any(~isfinite(s.intersection_pt_mm)), return; end
xt = s.intersection_pt_mm(1);
yb = baseline_y_at(s, xt);
if ~isfinite(yb), return; end
fx = @(x) x - xt;
fy = @(y) yb - y;

sides = {'left', 'right'};
for i = 1:2
    h = c.(sides{i});
    h.x_mm = fx(h.x_mm);  h.y_mm = fy(h.y_mm);
    if ~isempty(h.xfit_mm), h.xfit_mm = fx(h.xfit_mm); end
    if ~isempty(h.yfit_mm), h.yfit_mm = fy(h.yfit_mm); end
    c.(sides{i}) = h;
end
c.p_left  = poly_center(s.p_left,  xt, yb);
c.p_right = poly_center(s.p_right, xt, yb);

if isfield(c, 'local_fit') && isstruct(c.local_fit) && isfield(c.local_fit, 'used') && c.local_fit.used
    lf = c.local_fit;
    lf.p_left  = poly_center(lf.p_left,  xt, yb);
    lf.p_right = poly_center(lf.p_right, xt, yb);
    lf.xfit_left_mm  = fx(lf.xfit_left_mm);   lf.yfit_left_mm  = fy(lf.yfit_left_mm);
    lf.xfit_right_mm = fx(lf.xfit_right_mm);  lf.yfit_right_mm = fy(lf.yfit_right_mm);
    c.local_fit = lf;
end

c.intersection_pt_mm = [fx(xt), fy(s.intersection_pt_mm(2))];
if isfield(c, 'intersection_pt_mm_global') && numel(c.intersection_pt_mm_global) == 2
    c.intersection_pt_mm_global = [fx(c.intersection_pt_mm_global(1)), fy(c.intersection_pt_mm_global(2))];
end

% baseline: pivot moves with the points; a (small) residual tilt flips sign with y
c.level.pivot_mm      = [fx(s.level.pivot_mm(1)), fy(s.level.pivot_mm(2))];
c.level.baseline_y_mm = fy(s.level.baseline_y_mm);
if ~s.level.applied   % leveled peaks have a horizontal baseline; keep their tilt for the title
    c.level.tilt_deg  = -s.level.tilt_deg;
end

c.height.baseline_y_mm = fy(s.height.baseline_y_mm);
c.height.apex_x_mm     = fx(s.height.apex_x_mm);
c.height.apex_y_mm     = fy(s.height.apex_y_mm);
ok = true;
end


function q = poly_center(p, xt, yb)
% Coefficients of q(x) = yb - p(x + xt), same length as p.
if isempty(p) || any(~isfinite(p)), q = p; return; end
p = p(:).';
q = p(1);
for i = 2:numel(p)
    q = conv(q, [1 xt]);          % Horner step: q*(x + xt) + p(i)
    q(end) = q(end) + p(i);
end
q = -q;
q(end) = q(end) + yb;
end


function [rc, rb, ok] = center_raw(r, s, scale)
% CENTER_RAW  Center the raw (as-saved) profile on the same tip: map the
% final tip back to the raw frame (undo the scaling, then the leveling
% rotation), put it at x = 0, and set y = 0 at the raw (tilted) baseline
% directly below it, with y up. The raw tilt is kept so it stays visible.
% rb = [x1 x2; y1 y2] is that tilted baseline in the centered raw frame.
rc = r;  rb = [];  ok = false;
if isempty(s.intersection_pt_mm) || any(~isfinite(s.intersection_pt_mm)) || ...
        any(~isfinite(s.level.pivot_mm)) || ~isfinite(s.level.tilt_deg) || scale == 0
    return;
end
piv = s.level.pivot_mm / scale;          % the rotation pivot is fixed by the rotation
xt = s.intersection_pt_mm(1) / scale;
yt = s.intersection_pt_mm(2) / scale;
phi = deg2rad(s.level.tilt_deg);
if s.level.applied
    [xt, ~] = rotate_pts(xt, yt, piv(1), piv(2), -phi);   % undo the leveling rotation
end
ybase = @(x) piv(2) + tan(phi) * (x - piv(1));       % raw baseline (tilted)
yb0 = ybase(xt);

rc.left.x_mm  = r.left.x_mm  - xt;   rc.left.y_mm  = yb0 - r.left.y_mm;
rc.right.x_mm = r.right.x_mm - xt;   rc.right.y_mm = yb0 - r.right.y_mm;
xx = [min(rc.left.x_mm), max(rc.right.x_mm)];
if all(isfinite(xx))
    rb = [xx; yb0 - ybase(xx + xt)];
end
ok = true;
end


function [ax, figs] = showcase_axes(tlo, separate, figs, name, span)
% Next axes for the showcase: a tile of the shared figure (span = number of
% columns it covers), or a new figure.
if nargin < 5, span = 1; end
if separate
    figs(end+1) = figure('Name', name, 'NumberTitle', 'off', 'Color', 'w');
    ax = axes(figs(end));
elseif span > 1
    ax = nexttile(tlo, [1 span]);
else
    ax = nexttile(tlo);
end
end


function lf = tip_line_fits(s, win_frac)
% Straight-line fits to the points within +/- window of the tip, exactly as
% refine_peak_angle does it. If the pipeline already used them, they are
% taken from s.local_fit; otherwise they are computed here for display.
lf = struct('ok', false, 'used', false, 'pL', [], 'pR', [], 'win', NaN, 'center', NaN, ...
    'total_range', NaN, 'xL', [], 'yL', [], 'xR', [], 'yR', [], ...
    'xt', NaN, 'yt', NaN, 'thL', NaN, 'thR', NaN);
if isempty(s.intersection_pt_mm) || any(~isfinite(s.intersection_pt_mm)), return; end

% refine_peak_angle centres its window on the tip found by the global fits
if isfield(s, 'intersection_pt_mm_global') && ~isempty(s.intersection_pt_mm_global) && ...
        all(isfinite(s.intersection_pt_mm_global))
    xc = s.intersection_pt_mm_global(1);
else
    xc = s.intersection_pt_mm(1);
end
lf.center = xc;
lf.total_range = max(s.right.x_mm) - min(s.left.x_mm);
if ~isfinite(lf.total_range) || lf.total_range <= 0, return; end

okL = isfinite(s.left.x_mm)  & isfinite(s.left.y_mm);
okR = isfinite(s.right.x_mm) & isfinite(s.right.y_mm);
used = isfield(s, 'local_fit') && isstruct(s.local_fit) && isfield(s.local_fit, 'used') && s.local_fit.used;
if used
    w = s.local_fit.window_mm;
else
    w = win_frac * lf.total_range;
    for attempt = 1:5
        mL = okL & abs(s.left.x_mm  - xc) <= w;
        mR = okR & abs(s.right.x_mm - xc) <= w;
        if nnz(mL) >= 3 && nnz(mR) >= 3, break; end
        w = 2 * w;
    end
end
mL = okL & abs(s.left.x_mm  - xc) <= w;
mR = okR & abs(s.right.x_mm - xc) <= w;
if nnz(mL) < 2 || nnz(mR) < 2, return; end

lf.xL = s.left.x_mm(mL);   lf.yL = s.left.y_mm(mL);
lf.xR = s.right.x_mm(mR);  lf.yR = s.right.y_mm(mR);
if used
    lf.pL = s.local_fit.p_left;  lf.pR = s.local_fit.p_right;
else
    lf.pL = polyfit(lf.xL(:), lf.yL(:), 1);
    lf.pR = polyfit(lf.xR(:), lf.yR(:), 1);
end
if abs(lf.pL(1) - lf.pR(1)) < eps, return; end   % parallel lines: no crossing
lf.xt = (lf.pR(2) - lf.pL(2)) / (lf.pL(1) - lf.pR(1));
lf.yt = polyval(lf.pL, lf.xt);
lf.thL = atand(abs(lf.pL(1)));
lf.thR = atand(abs(lf.pR(1)));
lf.win = w;
lf.used = used;
lf.ok = true;
end


% -------------------------- step_through_peaks --------------------
function step_through_peaks(orig_info, final_info, varargin)
% STEP_THROUGH_PEAKS  Draw each peak in a single reused figure, clearing
%                      it between peaks. Put a breakpoint on the line
%                      marked BREAKPOINT to pause after each peak is drawn;
%                      press Continue (F5) to move to the next one.

orig_items  = collect_structs(orig_info);
final_items = collect_structs(final_info);
n = numel(final_items);
if numel(orig_items) ~= n
    error('step_through_peaks: orig_info and final_info must hold the same number of peaks.');
end

fig = figure('Name', 'Peak viewer', 'NumberTitle', 'off', ...
             'Units', 'normalized', 'Position', [0.1 0.1 0.8 0.75]);

for k = 1:n
    if ~isvalid(fig), break; end      % stop if you closed the window
    clf(fig);                          % clear the previous peak

    f = final_items{k};
    o = orig_items{k};
    ttl = sprintf('Peak %d of %d', k, n);

    if ~isstruct(f) || ~isfield(f, 'left') || ~isfield(f, 'right')
        ax = axes(fig);
        text(0.5, 0.5, sprintf('%s: no data', ttl), 'Units', 'normalized', ...
            'HorizontalAlignment', 'center', 'Parent', ax);
        axis(ax, 'off');
    else
        was_leveled = isfield(f, 'level') && isstruct(f.level) && ...
            isfield(f.level, 'applied') && f.level.applied;

        if was_leveled && isstruct(o) && isfield(o, 'left') && isfield(o, 'right')
            tlo = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
            ax1 = nexttile(tlo);
            plot_mm_fits(ax1, o, sprintf('%s - as saved (tilt %.2f deg)', ttl, f.level.tilt_deg), true);
            ax2 = nexttile(tlo);
            plot_mm_fits(ax2, f, ttl);
        else
            ax = axes(fig);
            plot_mm_fits(ax, f, ttl);
        end
    end

    drawnow;                           % make sure the plot is on screen
    current_peak = k;                  % <-- BREAKPOINT: set it on this line
end

end


% ---------------------------- compute_arclength -------------------
function angle_info_out = compute_arclength(angle_info, varargin)
% COMPUTE_ARCLENGTH  Total arclength (mm) of the displayed profile
% (left + right edge, including the join between them).
%   arclength.data_mm : polyline through the (lightly smoothed) edge points
%   arclength.fit_mm  : integral of sqrt(1+y'^2) over the polynomial fits
% Both are unchanged by the leveling rotation (rotation preserves length).
p = inputParser;
addParameter(p, 'SmoothPts', 5);   % moving-mean window for the data estimate (1 = none)
addParameter(p, 'Unscale', 1);     % multiplies the reported lengths (1/profile_scale restores the original arclength)
parse(p, varargin{:});
opt = p.Results;

if iscell(angle_info)
    items = angle_info;
    was_cell = true;
else
    items = num2cell(angle_info(:)');
    was_cell = false;
end

for k = 1:numel(items)
    items{k} = arclength_one(items{k}, opt);
end

if was_cell
    angle_info_out = items;
else
    angle_info_out = reshape([items{:}], size(angle_info));
end

end


function s = arclength_one(s, opt)

if ~isstruct(s), return; end   % empty / missing entry: leave as-is
s = ensure_fields(s);
s.arclength = struct('data_mm', NaN, 'fit_mm', NaN);

[xl, yl] = sorted_pts(s.left.x_mm,  s.left.y_mm);
[xr, yr] = sorted_pts(s.right.x_mm, s.right.y_mm);
if isempty(xl) || isempty(xr)
    return;
end

% ---- data polyline (smooth y a little to suppress the pixel staircase) ----
if opt.SmoothPts > 1
    yls = movmean(yl, opt.SmoothPts);
    yrs = movmean(yr, opt.SmoothPts);
else
    yls = yl;  yrs = yr;
end
X = [xl; xr];  Y = [yls; yrs];     % left profile lies to the left of the right one
s.arclength.data_mm = sum(hypot(diff(X), diff(Y)));

% ---- fit-based: each fit over its own x-range, plus the join ----
if all(isfinite(s.p_left)) && all(isfinite(s.p_right))
    LL = fit_len(s.p_left,  min(xl), max(xl));
    LR = fit_len(s.p_right, min(xr), max(xr));
    join = hypot(min(xr) - max(xl), ...
        polyval(s.p_right, min(xr)) - polyval(s.p_left, max(xl)));
    s.arclength.fit_mm = LL + LR + join;
end

% report in the original (unscaled) units
s.arclength.data_mm = s.arclength.data_mm * opt.Unscale;
s.arclength.fit_mm  = s.arclength.fit_mm  * opt.Unscale;

end


function [x, y] = sorted_pts(x, y)
% Column vectors of finite points, sorted by x.
x = x(:);  y = y(:);
ok = isfinite(x) & isfinite(y);
x = x(ok);  y = y(ok);
[x, o] = sort(x);
y = y(o);
end


function L = fit_len(p, x1, x2)
% Arclength of polynomial p over [x1, x2].
xf = linspace(x1, x2, 2000);
dy = polyval(polyder(p), xf);
L = trapz(xf, sqrt(1 + dy.^2));
end


% ---------------------------- compute_height ----------------------
function angle_info_out = compute_height(angle_info, varargin)
% COMPUTE_HEIGHT  Estimate each peak's height above its baseline.
%
%   out = compute_height(angle_info, 'EndSlopeTol', 5, 'SmoothPts', 21)
%
%   height = (baseline y at the tip's x) - (tip y). y_mm grows downward,
%   so a peak sticking up from the baseline gives a positive height.
%   The baseline is the one estimated by level_baseline (horizontal
%   through the pivot for leveled peaks, otherwise the slightly tilted
%   line through the pivot), so run level_baseline first.
%
%   Adds a 'height' sub-struct: height_tip_mm, height_apex_mm,
%   apex_x_mm, apex_y_mm, baseline_y_mm, baseline_ok.

p = inputParser;
addParameter(p, 'EndSlopeTol', 5);
addParameter(p, 'SmoothPts', 21);
addParameter(p, 'HeightScale', 1);   % multiplies the reported heights only
parse(p, varargin{:});
opt = p.Results;

if iscell(angle_info)
    items = angle_info;
    was_cell = true;
else
    items = num2cell(angle_info(:)');
    was_cell = false;
end

for k = 1:numel(items)
    items{k} = height_one(items{k}, opt);
end

if was_cell
    angle_info_out = items;
else
    angle_info_out = reshape([items{:}], size(angle_info));
end

end


function s = height_one(s, opt)

if ~isstruct(s), return; end   % empty / missing entry: leave as-is
s = ensure_fields(s);

if isempty(s.intersection_pt_mm) || any(~isfinite(s.intersection_pt_mm))
    return;
end
xt = s.intersection_pt_mm(1);
yt = s.intersection_pt_mm(2);

by = baseline_y_at(s, xt);
if ~isfinite(by)
    return;
end
s.height.baseline_y_mm = by;
s.height.height_tip_mm = (by - yt) * opt.HeightScale;

% Data-based apex: highest point of a median-smoothed copy of the profile
X = [s.left.x_mm(:);  s.right.x_mm(:)];
Y = [s.left.y_mm(:);  s.right.y_mm(:)];
ok = isfinite(X) & isfinite(Y);
X = X(ok);  Y = Y(ok);
if numel(Y) >= opt.SmoothPts
    [X, ord] = sort(X);
    Y = Y(ord);
    Ys = movmedian(Y, opt.SmoothPts);
    [ya, ia] = min(Ys);
    s.height.apex_x_mm = X(ia);
    s.height.apex_y_mm = ya;
    s.height.height_apex_mm = (baseline_y_at(s, X(ia)) - ya) * opt.HeightScale;
end

es = s.level.end_slope_deg;
s.height.baseline_ok = all(isfinite(es)) && all(abs(es) <= opt.EndSlopeTol);

end


function by = baseline_y_at(s, x)
% y of the baseline at x (NaN if it isn't known). Leveled peaks have a
% horizontal baseline through the pivot; otherwise the baseline is the
% line through the pivot at the measured (small) tilt.
by = NaN(size(x));
if ~isfield(s, 'level') || ~isstruct(s.level) || ~isfield(s.level, 'pivot_mm') || ...
        any(~isfinite(s.level.pivot_mm))
    return;
end
piv = s.level.pivot_mm;
if s.level.applied
    by = piv(2) + 0*x;
elseif isfinite(s.level.tilt_deg)
    by = piv(2) + tand(s.level.tilt_deg) * (x - piv(1));
end
end


% ---------------------------- level_baseline ----------------------
function angle_info_out = level_baseline(angle_info, varargin)
% LEVEL_BASELINE  Rotate each peak so its baseline is horizontal, then
%                  refit the left/right polynomials in the rotated frame.
%
%   out = level_baseline(angle_info, 'TiltTol', 0.5, 'EndFrac', 0.10)
%
%   The baseline is the line joining the outer ends of the two profiles
%   (median of the first EndFrac of the left profile and last EndFrac of
%   the right profile). If tilted by more than TiltTol degrees, all
%   points are rotated about the midpoint of the two ends and the
%   polynomials are refit. Run BEFORE fix_intersection.
%
%   Adds/updates a 'level' sub-struct: applied, tilt_deg, dy_mm,
%   pivot_mm, baseline_y_mm, end_slope_deg, p_left_orig / p_right_orig.

p = inputParser;
addParameter(p, 'EndFrac', 0.10);
addParameter(p, 'TiltTol', 0.5);
addParameter(p, 'Degree', []);
parse(p, varargin{:});
opt = p.Results;

if iscell(angle_info)
    items = angle_info;
    was_cell = true;
else
    items = num2cell(angle_info(:)');
    was_cell = false;
end

for k = 1:numel(items)
    items{k} = level_one(items{k}, opt, k);
end

if was_cell
    angle_info_out = items;
else
    angle_info_out = reshape([items{:}], size(angle_info));
end

end


function s = level_one(s, opt, k)

if ~isstruct(s), return; end   % empty / missing entry: leave as-is
s = ensure_fields(s);

xl = s.left.x_mm;   yl = s.left.y_mm;
xr = s.right.x_mm;  yr = s.right.y_mm;
if isempty(xl) || isempty(xr) || isempty(yl) || isempty(yr)
    return;
end
okL = isfinite(xl) & isfinite(yl);
okR = isfinite(xr) & isfinite(yr);
if nnz(okL) < 10 || nnz(okR) < 10
    return;
end

% Outer end regions (medians, so stray points don't matter)
xlo = xl(okL);  ylo = yl(okL);
xro = xr(okR);  yro = yr(okR);
selL = xlo <= min(xlo) + opt.EndFrac * (max(xlo) - min(xlo));
selR = xro >= max(xro) - opt.EndFrac * (max(xro) - min(xro));
xL0 = median(xlo(selL));  yL0 = median(ylo(selL));
xR0 = median(xro(selR));  yR0 = median(yro(selR));

phi = atan2(yR0 - yL0, xR0 - xL0);   % tilt of the line joining the two ends
x0 = (xL0 + xR0) / 2;
y0 = (yL0 + yR0) / 2;
if ~isfinite(phi) || ~isfinite(x0) || ~isfinite(y0)
    return;
end

% How flat is each end relative to the baseline? (an end that is still on
% the peak's flank means the baseline, and so the height, is unreliable)
s.level.end_slope_deg = [end_slope(xlo(selL), ylo(selL)), end_slope(xro(selR), yro(selR))] - rad2deg(phi);

s.level.tilt_deg      = rad2deg(phi);
s.level.dy_mm         = yR0 - yL0;
s.level.pivot_mm      = [x0, y0];
s.level.baseline_y_mm = y0;

if abs(s.level.tilt_deg) <= opt.TiltTol
    return;   % already level enough
end

[xl2, yl2] = rotate_pts(xl, yl, x0, y0, phi);
[xr2, yr2] = rotate_pts(xr, yr, x0, y0, phi);

if ~isempty(opt.Degree)
    deg = opt.Degree;
elseif numel(s.p_left) >= 2 && all(isfinite(s.p_left))
    deg = numel(s.p_left) - 1;
else
    deg = 5;
end

okL2 = isfinite(xl2) & isfinite(yl2);
okR2 = isfinite(xr2) & isfinite(yr2);
if nnz(okL2) < deg + 1 || nnz(okR2) < deg + 1
    warning('level_baseline: struct %d has too few points to refit after rotating; left unrotated.', k);
    return;
end

ws = warning('off', 'MATLAB:polyfit:RepeatedPointsOrRescale');
p_left_new  = polyfit(xl2(okL2), yl2(okL2), deg);
p_right_new = polyfit(xr2(okR2), yr2(okR2), deg);
warning(ws);

s.level.p_left_orig  = s.p_left;
s.level.p_right_orig = s.p_right;

s.p_left  = p_left_new;
s.p_right = p_right_new;

s.left.x_mm = xl2;   s.left.y_mm = yl2;
s.right.x_mm = xr2;  s.right.y_mm = yr2;
s.left.xfit_mm  = linspace(min(xl2), max(xl2), 200);
s.left.yfit_mm  = polyval(p_left_new, s.left.xfit_mm);
s.right.xfit_mm = linspace(min(xr2), max(xr2), 200);
s.right.yfit_mm = polyval(p_right_new, s.right.xfit_mm);

s.level.applied = true;

end


function a = end_slope(x, y)
% Angle (deg) of a straight-line fit through the points; NaN if it can't be fit.
if numel(x) < 3 || max(x) - min(x) <= 0
    a = NaN;
    return;
end
pf = polyfit(x(:), y(:), 1);
a = rad2deg(atan(pf(1)));
end


function [xo, yo] = rotate_pts(x, y, x0, y0, phi)
% Rotate points by -phi about (x0, y0): a baseline tilted by phi becomes
% horizontal.
c = cos(phi);  sn = sin(phi);
dx = x - x0;   dy = y - y0;
xo =  c*dx + sn*dy + x0;
yo = -sn*dx + c*dy + y0;
end


% ------------------------- fix_intersection ----------------------
function angle_info_fixed = fix_intersection(angle_info)
% FIX_INTERSECTION  Recompute the left/right polynomial intersection
%                    point and angle for angle_finder output(s).
%
%   Picks the real root of (p_left - p_right) closest to the boundary
%   between the two profiles. If no root lies within 5% of the total
%   x-range of the join, falls back to the join itself, evaluating each
%   fit at its own end. Adds tip_info (method, gap_mm, slopes_opposite).

if iscell(angle_info)
    items = angle_info;
    was_cell = true;
else
    items = num2cell(angle_info(:)');
    was_cell = false;
end

for k = 1:numel(items)
    items{k} = fix_one(items{k}, k);
end

if was_cell
    angle_info_fixed = items;
else
    angle_info_fixed = reshape([items{:}], size(angle_info));
end

end


function s = fix_one(s, k)

if ~isstruct(s), return; end   % empty / missing entry: leave as-is
s = ensure_fields(s);

ROOT_TOL = 0.05;   % trust a root only if within this fraction of the total
                   % x-range of the join between the two profiles

p_left = s.p_left;
p_right = s.p_right;

if any(~isfinite(p_left)) || any(~isfinite(p_right))
    warning('fix_intersection: struct %d has an incomplete polynomial fit; left unchanged.', k);
    return;
end
if isempty(s.left.x_mm) || isempty(s.right.x_mm)
    warning('fix_intersection: struct %d is missing left/right x_mm data; left unchanged.', k);
    return;
end

xl_end   = max(s.left.x_mm);     % right edge of the left profile
xr_start = min(s.right.x_mm);    % left edge of the right profile
xb = (xl_end + xr_start) / 2;    % where the two profiles meet
total_range = max(s.right.x_mm) - min(s.left.x_mm);

dp_left  = polyder(p_left);
dp_right = polyder(p_right);

% Difference polynomial (pad to equal length, just in case)
L = max(numel(p_left), numel(p_right));
a = [zeros(1, L-numel(p_left)), p_left];
b = [zeros(1, L-numel(p_right)), p_right];
r = roots(a - b);
r = real(r(abs(imag(r)) < 1e-6));

use_root = false;
if ~isempty(r)
    [dmin, idx] = min(abs(r - xb));
    use_root = dmin <= ROOT_TOL * total_range;
end

if use_root
    method = 'root';
    xint = r(idx);
    yint = polyval(p_left, xint);
    m1 = polyval(dp_left,  xint);
    m2 = polyval(dp_right, xint);
else
    % The fits don't cross near the join: use the join itself, with each
    % fit evaluated at its own end so nothing is extrapolated.
    method = 'junction';
    xint = xb;
    yint = (polyval(p_left, xl_end) + polyval(p_right, xr_start)) / 2;
    m1 = polyval(dp_left,  xl_end);
    m2 = polyval(dp_right, xr_start);
end

angle_deg = rad2deg(atan(abs((m2 - m1) / (1 + m1*m2))));

s.intersection_pt_mm = [xint, yint];
s.angle_deg = angle_deg;
% y_mm grows downward, so at a real apex the left slope is negative and
% the right slope positive.
s.tip_info = struct('method', method, ...
    'gap_mm', abs(polyval(p_left, xl_end) - polyval(p_right, xr_start)), ...
    'slopes_opposite', (m1 < 0) && (m2 > 0));

end


% ------------------------ refine_peak_angle -----------------------
function angle_info_refined = refine_peak_angle(angle_info, varargin)
% REFINE_PEAK_ANGLE  Refit a low-degree polynomial to just the points
%                     near the peak tip, to correct for angles that are
%                     underestimated when a single high-order fit gets
%                     pulled by local flattening near the top.
%
% Name-Value parameters: 'AngleThreshold' (30), 'Degree' (1),
% 'WindowMM' ([]), 'WindowFrac' (0.10), 'MinPoints' (Degree+2),
% 'MaxExpand' (5).
%
% Each struct gets a 'local_fit' sub-struct. When refinement is applied,
% angle_deg / intersection_pt_mm are overwritten and the previous values
% are kept as angle_deg_global / intersection_pt_mm_global.

p = inputParser;
addParameter(p, 'AngleThreshold', 30);
addParameter(p, 'Degree', 1);
addParameter(p, 'WindowMM', []);
addParameter(p, 'WindowFrac', 0.10);
addParameter(p, 'MinPoints', []);
addParameter(p, 'MaxExpand', 5);
parse(p, varargin{:});
opt = p.Results;
if isempty(opt.MinPoints)
    opt.MinPoints = opt.Degree + 2;
end

if iscell(angle_info)
    items = angle_info;
    was_cell = true;
else
    items = num2cell(angle_info(:)');
    was_cell = false;
end

for k = 1:numel(items)
    items{k} = refine_one(items{k}, opt, k);
end

if was_cell
    angle_info_refined = items;
else
    angle_info_refined = reshape([items{:}], size(angle_info));
end

end


function s = refine_one(s, opt, k)

if ~isstruct(s), return; end   % empty / missing entry: leave as-is
s = ensure_fields(s);

s.local_fit = struct('used', false, 'degree', opt.Degree, 'window_mm', NaN, ...
    'n_left', 0, 'n_right', 0, 'p_left', [], 'p_right', [], ...
    'xfit_left_mm', [], 'yfit_left_mm', [], 'xfit_right_mm', [], 'yfit_right_mm', []);

% Always carry these fields, even when no refinement happens, so every
% element of the struct array ends up with the same field set (otherwise
% concatenating them with [items{:}] throws a horzcat error).
s.angle_deg_global = s.angle_deg;
s.intersection_pt_mm_global = s.intersection_pt_mm;

if isnan(s.angle_deg) || s.angle_deg > opt.AngleThreshold
    return; % angle already large enough (or undefined) -- leave as-is
end
if isempty(s.left.x_mm) || isempty(s.right.x_mm) || isempty(s.intersection_pt_mm)
    warning('refine_peak_angle: struct %d missing data needed for refinement; skipped.', k);
    return;
end

xint = s.intersection_pt_mm(1);
total_range = max(s.right.x_mm) - min(s.left.x_mm);
if ~isfinite(total_range) || total_range <= 0
    warning('refine_peak_angle: struct %d has an invalid x-range; skipped.', k);
    return;
end

if isempty(opt.WindowMM)
    window = opt.WindowFrac * total_range;
else
    window = opt.WindowMM;
end

for attempt = 1:opt.MaxExpand
    maskL = ~isnan(s.left.x_mm) & ~isnan(s.left.y_mm) & ...
        s.left.x_mm >= xint - window & s.left.x_mm <= xint + window;
    maskR = ~isnan(s.right.x_mm) & ~isnan(s.right.y_mm) & ...
        s.right.x_mm >= xint - window & s.right.x_mm <= xint + window;
    if sum(maskL) >= opt.MinPoints && sum(maskR) >= opt.MinPoints
        break;
    end
    window = window * 2;
end

if sum(maskL) < opt.MinPoints || sum(maskR) < opt.MinPoints
    warning('refine_peak_angle: struct %d has too few points near the tip after expanding the window; skipped.', k);
    return;
end

xl_loc = s.left.x_mm(maskL);  yl_loc = s.left.y_mm(maskL);
xr_loc = s.right.x_mm(maskR); yr_loc = s.right.y_mm(maskR);

p_left_loc  = polyfit(xl_loc, yl_loc, opt.Degree);
p_right_loc = polyfit(xr_loc, yr_loc, opt.Degree);

% Intersection of the local fits: root of their difference closest to
% the original tip x-position.
L = max(numel(p_left_loc), numel(p_right_loc));
a = [zeros(1, L-numel(p_left_loc)), p_left_loc];
b = [zeros(1, L-numel(p_right_loc)), p_right_loc];
pdiff = a - b;
r = roots(pdiff);
r = real(r(abs(imag(r)) < 1e-6));

if isempty(r)
    warning('refine_peak_angle: struct %d local fits do not cross; skipped.', k);
    return;
end
[~, idx] = min(abs(r - xint));
xint_loc = r(idx);
yint_loc = polyval(p_left_loc, xint_loc);

dpL = polyder(p_left_loc);
dpR = polyder(p_right_loc);
m1 = polyval(dpL, xint_loc);
m2 = polyval(dpR, xint_loc);
angle_deg_loc = rad2deg(atan(abs((m2 - m1) / (1 + m1*m2))));

s.angle_deg = angle_deg_loc;
s.intersection_pt_mm = [xint_loc, yint_loc];

s.local_fit.used = true;
s.local_fit.window_mm = window;
s.local_fit.n_left = sum(maskL);
s.local_fit.n_right = sum(maskR);
s.local_fit.p_left = p_left_loc;
s.local_fit.p_right = p_right_loc;
s.local_fit.xfit_left_mm  = linspace(min(xl_loc), max(xl_loc), 50);
s.local_fit.yfit_left_mm  = polyval(p_left_loc, s.local_fit.xfit_left_mm);
s.local_fit.xfit_right_mm = linspace(min(xr_loc), max(xr_loc), 50);
s.local_fit.yfit_right_mm = polyval(p_right_loc, s.local_fit.xfit_right_mm);

end


% ---------------------------- compute_theta_c -----------------------
function angle_info_out = compute_theta_c(angle_info, varargin)
% COMPUTE_THETA_C  Compute theta_c (angle between the horizontal and the
%                   flank's tangent at the crease/apex) for the left and
%                   right flanks separately:
%       theta_c_side = atan(|slope at tip|)   (degrees, magnitude only)
%
%   'Tolerance' (default 5 deg): if |theta_c_left - theta_c_right|
%   exceeds this, theta_c.asymmetric is set true.
%
%   Adds a 'theta_c' sub-struct: left_deg, right_deg, sym_deg, diff_deg,
%   asymmetric. Uses the local (near-tip) fit if refine_peak_angle was
%   run, otherwise the global polynomial fit.

p = inputParser;
addParameter(p, 'Tolerance', 5);
parse(p, varargin{:});
tol = p.Results.Tolerance;

if iscell(angle_info)
    items = angle_info;
    was_cell = true;
else
    items = num2cell(angle_info(:)');
    was_cell = false;
end

for k = 1:numel(items)
    items{k} = theta_c_one(items{k}, tol);
end

if was_cell
    angle_info_out = items;
else
    angle_info_out = reshape([items{:}], size(angle_info));
end

end


function s = theta_c_one(s, tol)

if ~isstruct(s), return; end   % empty / missing entry: leave as-is
s = ensure_fields(s);

[m1, m2] = get_tip_slopes(s);

if isnan(m1) || isnan(m2)
    s.theta_c = struct('left_deg', NaN, 'right_deg', NaN, 'sym_deg', NaN, ...
        'diff_deg', NaN, 'asymmetric', false);
    return;
end

theta_L = rad2deg(atan(abs(m1)));
theta_R = rad2deg(atan(abs(m2)));

s.theta_c = struct( ...
    'left_deg', theta_L, ...
    'right_deg', theta_R, ...
    'sym_deg', (theta_L + theta_R)/2, ...
    'diff_deg', abs(theta_L - theta_R), ...
    'asymmetric', abs(theta_L - theta_R) > tol);

end


function [m1, m2, xint, yint] = get_tip_slopes(s)
% Shared helper: get the tip x/y and the left/right slopes AT the tip,
% preferring the near-tip local fit (from refine_peak_angle) when
% present, else falling back to the global polynomial fit.
m1 = NaN; m2 = NaN; xint = NaN; yint = NaN;

if ~isfield(s, 'intersection_pt_mm') || isempty(s.intersection_pt_mm)
    return;
end

has_local = isfield(s, 'local_fit') && isstruct(s.local_fit) && ...
    isfield(s.local_fit, 'used') && s.local_fit.used;
if has_local
    p_left_arc  = s.local_fit.p_left;
    p_right_arc = s.local_fit.p_right;
elseif isfield(s, 'p_left') && isfield(s, 'p_right')
    p_left_arc  = s.p_left;
    p_right_arc = s.p_right;
else
    return;
end

if isempty(p_left_arc) || isempty(p_right_arc) || ...
        any(~isfinite(p_left_arc)) || any(~isfinite(p_right_arc))
    return;
end

xint = s.intersection_pt_mm(1);
yint = s.intersection_pt_mm(2);
m1 = polyval(polyder(p_left_arc), xint);
m2 = polyval(polyder(p_right_arc), xint);

end


% ---------------------------- apply_scale -------------------------
function angle_info_out = apply_scale(angle_info, f)
% APPLY_SCALE  Uniformly scale every mm quantity of the results by f
%               (x AND y), so the geometry stays self-consistent.
%
%   Run AFTER compute_theta_c and compute_height. Profile points, fit
%   curves, tip, baseline pivot, heights, end-to-end offset, fit gap,
%   window sizes... are all multiplied by f, and every polynomial
%   y = sum c_k x^k is replaced by c_k * f^(1-k) (the same curve, scaled).
%   Slopes are unchanged, so all angles (theta_c, tip angle, tilt) keep
%   their measured values, heights scale by f, h/(1-cos(theta)) scales by
%   f, and the arclength (computed afterwards) scales by f.

if iscell(angle_info)
    items = angle_info;
    was_cell = true;
else
    items = num2cell(angle_info(:)');
    was_cell = false;
end

for k = 1:numel(items)
    items{k} = scale_geom_one(items{k}, f);
end

if was_cell
    angle_info_out = items;
else
    angle_info_out = reshape([items{:}], size(angle_info));
end

end


function s = scale_geom_one(s, f)

if ~isstruct(s), return; end   % empty / missing entry: leave as-is
s = ensure_fields(s);

if f == 1, return; end

% profile points and global fit curves
sides = {'left', 'right'};
flds  = {'x_mm', 'y_mm', 'xfit_mm', 'yfit_mm'};
for i = 1:2
    for j = 1:numel(flds)
        if ~isempty(s.(sides{i}).(flds{j}))
            s.(sides{i}).(flds{j}) = s.(sides{i}).(flds{j}) * f;
        end
    end
end

% global polynomials (and the pre-leveling ones, if present)
s.p_left  = scale_poly(s.p_left,  f);
s.p_right = scale_poly(s.p_right, f);
if isfield(s, 'level') && isstruct(s.level)
    if isfield(s.level, 'p_left_orig'),  s.level.p_left_orig  = scale_poly(s.level.p_left_orig,  f); end
    if isfield(s.level, 'p_right_orig'), s.level.p_right_orig = scale_poly(s.level.p_right_orig, f); end
end

% near-tip local fit
if isfield(s, 'local_fit') && isstruct(s.local_fit) && isfield(s.local_fit, 'used') && s.local_fit.used
    lf = {'xfit_left_mm', 'yfit_left_mm', 'xfit_right_mm', 'yfit_right_mm'};
    for j = 1:numel(lf)
        s.local_fit.(lf{j}) = s.local_fit.(lf{j}) * f;
    end
    s.local_fit.window_mm = s.local_fit.window_mm * f;
    s.local_fit.p_left  = scale_poly(s.local_fit.p_left,  f);
    s.local_fit.p_right = scale_poly(s.local_fit.p_right, f);
end

% tip location and fit gap
s.intersection_pt_mm = s.intersection_pt_mm * f;
if isfield(s, 'intersection_pt_mm_global') && ~isempty(s.intersection_pt_mm_global)
    s.intersection_pt_mm_global = s.intersection_pt_mm_global * f;
end
s.tip_info.gap_mm = s.tip_info.gap_mm * f;

% baseline / level info (angles tilt_deg and end_slope_deg are unchanged)
s.level.dy_mm         = s.level.dy_mm * f;
s.level.pivot_mm      = s.level.pivot_mm * f;
s.level.baseline_y_mm = s.level.baseline_y_mm * f;

% heights and apex
s.height.baseline_y_mm  = s.height.baseline_y_mm  * f;
s.height.height_tip_mm  = s.height.height_tip_mm  * f;
s.height.height_apex_mm = s.height.height_apex_mm * f;
s.height.apex_x_mm      = s.height.apex_x_mm      * f;
s.height.apex_y_mm      = s.height.apex_y_mm      * f;

end


function p = scale_poly(p, f)
% Coefficients of y' = f*y(x'/f) for y = polyval(p, x): c_k -> c_k * f^(1-k).
if isempty(p), return; end
pw = numel(p) - 1 : -1 : 0;
p = p(:).' .* f .^ (1 - pw);
end


% ---------------------------- export_offsets ----------------------
function [dx, dy, ok] = export_offsets(e)
% Offsets used to center a peak for export: dx = tip x (subtract it so the tip is at x = 0),
% dy = baseline y at the tip (the exports subtract the whole baseline line instead, via
% baseline_y_at, so the baseline is y = 0 along the entire profile). ok = false if there is
% no usable tip/baseline.
dx = NaN;  dy = NaN;  ok = false;
if isempty(e.intersection_pt_mm) || any(~isfinite(e.intersection_pt_mm)), return; end
dx = e.intersection_pt_mm(1);
dy = baseline_y_at(e, dx);
ok = isfinite(dy);
end


% ---------------------------- collect_structs ---------------------
function items = collect_structs(x)
% Flatten a struct, struct array, or (possibly nested) cell array of
% them into a 1xN cell array of 1x1 structs.
if isstruct(x) && ~isempty(x)
    items = num2cell(x(:)');
elseif iscell(x)
    items = {};
    for i = 1:numel(x)
        items = [items, collect_structs(x{i})]; %#ok<AGROW>
    end
else
    items = {[]};   % empty / non-struct entry: keep a placeholder so peak numbering is preserved
end
end


function s = ensure_fields(s)
% Fill in any fields angle_finder leaves out (or leaves empty) when a peak
% has no usable angle, so every entry has the same fields and the rest
% of the pipeline can run on it (it just reports NaN / 'no data').
if ~isfield(s, 'p_left'),  s.p_left  = NaN; end
if ~isfield(s, 'p_right'), s.p_right = NaN; end
if ~isfield(s, 'angle_deg') || isempty(s.angle_deg), s.angle_deg = NaN; end
if ~isfield(s, 'intersection_pt_mm'), s.intersection_pt_mm = []; end
if ~isfield(s, 'tip_info')
    s.tip_info = struct('method', 'none', 'gap_mm', NaN, 'slopes_opposite', false);
end
if ~isfield(s, 'level')
    s.level = struct('applied', false, 'tilt_deg', 0, 'dy_mm', 0, ...
        'pivot_mm', [NaN NaN], 'baseline_y_mm', NaN, 'end_slope_deg', [NaN NaN], ...
        'p_left_orig', [], 'p_right_orig', []);
end
if ~isfield(s, 'height')
    s.height = struct('baseline_y_mm', NaN, 'height_tip_mm', NaN, 'height_apex_mm', NaN, ...
        'apex_x_mm', NaN, 'apex_y_mm', NaN, 'baseline_ok', false);
end
if ~isfield(s, 'arclength')
    s.arclength = struct('data_mm', NaN, 'fit_mm', NaN);
end
sides = {'left', 'right'};
flds  = {'x_mm', 'y_mm', 'xfit_mm', 'yfit_mm', 'top_pos', 'bot_pos', 'mean_pos'};
for i = 1:2
    nm = sides{i};
    if ~isfield(s, nm) || ~isstruct(s.(nm))
        s.(nm) = struct();
    end
    for j = 1:numel(flds)
        if ~isfield(s.(nm), flds{j})
            s.(nm).(flds{j}) = [];
        end
    end
end
end


% --------------------------- plot_fit_panels ----------------------
function plot_fit_panels(orig_info, final_info, varargin)
% PLOT_FIT_PANELS  Plot the mm-space fit + theta_c panel for each peak,
%                   adding the pre-leveling version alongside it for
%                   peaks whose tilt was corrected.

p = inputParser;
addParameter(p, 'Titles', {});
parse(p, varargin{:});
titles = p.Results.Titles;

orig_items  = collect_structs(orig_info);
final_items = collect_structs(final_info);
n = numel(final_items);
if numel(orig_items) ~= n
    error('plot_fit_panels: orig_info and final_info must hold the same number of peaks.');
end
if isempty(titles) || numel(titles) ~= n
    titles = arrayfun(@(k) sprintf('Peak %d', k), 1:n, 'UniformOutput', false);
end

figure('Name', 'Fits and theta_c', 'NumberTitle', 'off', ...
       'Units', 'normalized', 'Position', [0.05 0.05 0.9 0.9]);
tlo = tiledlayout(n, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tlo, 'Polynomial fits and theta_c (pre-leveling version shown where the tilt was corrected)');

for k = 1:n
    f = final_items{k};
    o = orig_items{k};

    if ~isstruct(f) || ~isfield(f, 'left') || ~isfield(f, 'right')
        ax = nexttile(tlo, [1 2]);
        text(0.5, 0.5, sprintf('%s: no data', titles{k}), 'Units', 'normalized', ...
            'HorizontalAlignment', 'center', 'Parent', ax);
        axis(ax, 'off');
        continue;
    end

    was_leveled = isfield(f, 'level') && isstruct(f.level) && ...
        isfield(f.level, 'applied') && f.level.applied;

    if was_leveled && isstruct(o) && isfield(o, 'left') && isfield(o, 'right')
        ax1 = nexttile(tlo);
        plot_mm_fits(ax1, o, sprintf('%s - as saved (tilt %.2f deg)', titles{k}, f.level.tilt_deg), true);
        ax2 = nexttile(tlo);
        plot_mm_fits(ax2, f, titles{k});   % title gets the '[leveled by ...]' tag
    else
        ax = nexttile(tlo, [1 2]);
        plot_mm_fits(ax, f, titles{k});
    end
end

end


% --------------------------- plot_profiles ------------------------
function plot_profiles(angle_info, varargin)
% PLOT_PROFILES  Visualize the left/right edge profiles and polynomial
%                fits: [ left pixel profile | right pixel profile |
%                mm-space fit & theta_c ] per peak.

p = inputParser;
addParameter(p, 'Titles', {});
parse(p, varargin{:});
titles = p.Results.Titles;

items = collect_structs(angle_info);

n = numel(items);
if isempty(titles)
    titles = arrayfun(@(k) sprintf('Peak %d', k), 1:n, 'UniformOutput', false);
elseif numel(titles) ~= n
    warning('Number of Titles (%d) does not match number of structs (%d); using defaults.', ...
        numel(titles), n);
    titles = arrayfun(@(k) sprintf('Peak %d', k), 1:n, 'UniformOutput', false);
end

figure('Name', 'Angle Finder Profiles', 'NumberTitle', 'off', ...
       'Units', 'normalized', 'Position', [0.05 0.05 0.9 0.85]);
tlo = tiledlayout(n, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
title(tlo, 'Edge profiles, fits, and theta_c');

for k = 1:n
    s = items{k};
    if ~isstruct(s) || ~isfield(s, 'left') || ~isfield(s, 'right')
        for c = 1:3
            axm = nexttile(tlo);
            text(0.5, 0.5, sprintf('%s: no data', titles{k}), 'Units', 'normalized', ...
                'HorizontalAlignment', 'center', 'Parent', axm);
            axis(axm, 'off');
        end
        continue;
    end

    ax1 = nexttile(tlo);
    plot_half_pixels(ax1, s.left, sprintf('%s - Left', titles{k}));

    ax2 = nexttile(tlo);
    plot_half_pixels(ax2, s.right, sprintf('%s - Right', titles{k}));

    ax3 = nexttile(tlo);
    plot_mm_fits(ax3, s, titles{k});
end

end % plot_profiles


function plot_half_pixels(ax, half, ttl)
% Plot top/bottom/mean pixel-row profiles for one half (left or right).
hold(ax, 'on');
has_data = false;

if isfield(half, 'top_pos') && ~isempty(half.top_pos)
    x = 1:numel(half.top_pos);
    valid = ~isnan(half.top_pos);
    if any(valid)
        plot(ax, x(valid), half.top_pos(valid), 'g.', 'MarkerSize', 6);
        has_data = true;
    end
end
if isfield(half, 'bot_pos') && ~isempty(half.bot_pos)
    x = 1:numel(half.bot_pos);
    valid = ~isnan(half.bot_pos);
    if any(valid)
        plot(ax, x(valid), half.bot_pos(valid), 'r.', 'MarkerSize', 6);
        has_data = true;
    end
end
if isfield(half, 'mean_pos') && ~isempty(half.mean_pos)
    x = 1:numel(half.mean_pos);
    valid = ~isnan(half.mean_pos);
    if any(valid)
        plot(ax, x(valid), half.mean_pos(valid), 'b-', 'LineWidth', 1);
        has_data = true;
    end
end

if has_data
    set(ax, 'YDir', 'reverse'); % row index increases downward, like image rows
    legend(ax, {'top', 'bottom', 'mean'}, 'Location', 'best');
else
    text(0.5, 0.5, 'no data', 'Units', 'normalized', ...
        'HorizontalAlignment', 'center', 'Parent', ax);
end

xlabel(ax, 'column (px)');
ylabel(ax, 'row (px)');
title(ax, ttl, 'Interpreter', 'none');
box(ax, 'on');
hold(ax, 'off');
end


function plot_mm_fits(ax, s, ttl, show_tilt_baseline)
% Plot mm-space edge points, fitted curves, intersection point, and the
% theta_c arcs at the tip. If show_tilt_baseline is true, also draw the
% (tilted) baseline estimated from the two ends of the profile.
if nargin < 4, show_tilt_baseline = false; end
hold(ax, 'on');
legend_entries = {};

if isfield(s.left, 'x_mm') && ~isempty(s.left.x_mm)
    plot(ax, s.left.x_mm, s.left.y_mm, 'bo', 'MarkerSize', 3);
    legend_entries{end+1} = 'left pts';
end
if isfield(s.right, 'x_mm') && ~isempty(s.right.x_mm)
    plot(ax, s.right.x_mm, s.right.y_mm, 'ro', 'MarkerSize', 3);
    legend_entries{end+1} = 'right pts';
end
if isfield(s.left, 'xfit_mm') && ~isempty(s.left.xfit_mm)
    plot(ax, s.left.xfit_mm, s.left.yfit_mm, 'b-', 'LineWidth', 1.5);
    legend_entries{end+1} = 'left fit';
end
if isfield(s.right, 'xfit_mm') && ~isempty(s.right.xfit_mm)
    plot(ax, s.right.xfit_mm, s.right.yfit_mm, 'r-', 'LineWidth', 1.5);
    legend_entries{end+1} = 'right fit';
end
if isfield(s, 'intersection_pt_mm') && ~isempty(s.intersection_pt_mm)
    plot(ax, s.intersection_pt_mm(1), s.intersection_pt_mm(2), ...
        'kp', 'MarkerSize', 12, 'MarkerFaceColor', 'y');
    legend_entries{end+1} = 'intersection';
end

% Overlay a local (near-tip) low-degree refit, if refine_peak_angle was run
has_local = isfield(s, 'local_fit') && isstruct(s.local_fit) && ...
    isfield(s.local_fit, 'used') && s.local_fit.used;
if has_local
    plot(ax, s.local_fit.xfit_left_mm, s.local_fit.yfit_left_mm, ...
        'c--', 'LineWidth', 1.5);
    plot(ax, s.local_fit.xfit_right_mm, s.local_fit.yfit_right_mm, ...
        'm--', 'LineWidth', 1.5);
    legend_entries{end+1} = 'left local fit';
    legend_entries{end+1} = 'right local fit';
end

if ~isempty(legend_entries)
    set(ax, 'YDir', 'reverse');
    legend(ax, legend_entries, 'Location', 'best');
else
    text(0.5, 0.5, 'no fit data', 'Units', 'normalized', ...
        'HorizontalAlignment', 'center', 'Parent', ax);
end

is_leveled = isfield(s, 'level') && isstruct(s.level) && isfield(s.level, 'applied') && s.level.applied;

% Baseline: grey for leveled / near-level peaks, red for the as-saved
% (tilted) panel
if ~isempty(s.left.x_mm) && ~isempty(s.right.x_mm)
    xx = [min(s.left.x_mm) max(s.right.x_mm)];
    yy = baseline_y_at(s, xx);
    if all(isfinite(yy))
        if show_tilt_baseline
            bcol = [0.85 0.1 0.1];
        else
            bcol = [0.5 0.5 0.5];
        end
        plot(ax, xx, yy, ':', 'Color', bcol, 'LineWidth', 1.2, 'HandleVisibility', 'off');
    end
end

% Peak height: vertical segment from the tip down to the baseline
if isfield(s, 'height') && isstruct(s.height) && isfinite(s.height.height_tip_mm) && ...
        isfield(s, 'intersection_pt_mm') && ~isempty(s.intersection_pt_mm)
    xt = s.intersection_pt_mm(1);
    yt = s.intersection_pt_mm(2);
    by = baseline_y_at(s, xt);
    if isfinite(by)
        plot(ax, [xt xt], [yt by], '-', 'Color', [0.1 0.5 0.1], 'LineWidth', 1.5, ...
            'HandleVisibility', 'off');
        text(ax, xt, (yt + by)/2, sprintf('  h = %.2f mm', s.height.height_tip_mm), ...
            'Color', [0.1 0.5 0.1], 'FontWeight', 'bold', 'FontSize', 8, ...
            'VerticalAlignment', 'middle');
    end
end

% Draw the theta_c arcs (horizontal reference vs. each flank at the tip)
[theta_L, theta_R] = draw_theta_c_arcs(ax, s);

xlabel(ax, 'x (mm)');
ylabel(ax, 'y (mm)');
line1 = ttl;
if is_leveled
    line1 = sprintf('%s [leveled by %.2f deg]', ttl, s.level.tilt_deg);
end
if ~isnan(theta_L) && ~isnan(theta_R)
    sym_deg_p  = (theta_L + theta_R) / 2;
    diff_deg_p = abs(theta_L - theta_R);
    line2 = sprintf('theta_c: L = %.2f deg, R = %.2f deg', theta_L, theta_R);
    line3 = sprintf('sym avg = %.2f deg (L-R diff = %.2f deg)', sym_deg_p, diff_deg_p);
    if isfield(s, 'arclength') && isstruct(s.arclength) && isfinite(s.arclength.fit_mm)
        line3 = sprintf('%s | arclength = %.2f mm (data %.2f)', line3, ...
            s.arclength.fit_mm, s.arclength.data_mm);
    end
    title(ax, {line1, line2, line3}, 'Interpreter', 'none');
else
    title(ax, {line1, 'theta_c n/a'}, 'Interpreter', 'none');
end
box(ax, 'on');
axis(ax, 'equal'); % keep x/y mm scale equal so the arcs aren't visually distorted
hold(ax, 'off');
end


function [theta_L, theta_R] = draw_theta_c_arcs(ax, s, names)
% names (optional): {left, right} text to show at the arcs instead of the
% angle values, e.g. {'\theta_L', '\theta_R'}.
if nargin < 3, names = {}; end
% Draw theta_c on each side of the tip, following the paper's Fig. 1:
% the angle between the horizontal (dashed line through the apex) and
% the flank's tangent at the crease. Returns [NaN NaN] if the tip/slopes
% aren't available.
theta_L = NaN;
theta_R = NaN;

[m1, m2, xint, yint] = get_tip_slopes(s);
if isnan(m1) || isnan(m2)
    return;
end

% y_mm increases downward (image row convention), so the flanks leave
% the tip in these directions: left flank toward -x, right toward +x.
dir_left  = [-1, -m1]; dir_left  = dir_left  / norm(dir_left);
dir_right = [ 1,  m2]; dir_right = dir_right / norm(dir_right);
ref_left  = [-1, 0];
ref_right = [ 1, 0];

% Radius: tied to the local-fit window if available, else a fraction of
% the overall left+right x-range
has_local = isfield(s, 'local_fit') && isstruct(s.local_fit) && ...
    isfield(s.local_fit, 'used') && s.local_fit.used;
if has_local && isfinite(s.local_fit.window_mm) && s.local_fit.window_mm > 0
    r = 0.4 * s.local_fit.window_mm;
else
    total_range = max(s.right.x_mm) - min(s.left.x_mm);
    if ~isfinite(total_range) || total_range <= 0
        total_range = 1;
    end
    r = 0.06 * total_range;
end

col_L = [0 0.35 0.65];
col_R = [0.75 0.30 0.05];

% Dashed horizontal reference through the apex (both sides)
plot(ax, [xint - 1.4*r, xint + 1.4*r], [yint yint], 'k--', ...
    'LineWidth', 1, 'HandleVisibility', 'off');

% Flank tangent rays leaving the tip
pL = [xint, yint] + 1.4*r*dir_left;
pR = [xint, yint] + 1.4*r*dir_right;
plot(ax, [xint pL(1)], [yint pL(2)], ':', 'Color', col_L, ...
    'LineWidth', 1.2, 'HandleVisibility', 'off');
plot(ax, [xint pR(1)], [yint pR(2)], ':', 'Color', col_R, ...
    'LineWidth', 1.2, 'HandleVisibility', 'off');

if isempty(names), names = {'', ''}; end
theta_L = draw_one_theta_arc(ax, xint, yint, ref_left,  dir_left,  r, col_L, names{1});
theta_R = draw_one_theta_arc(ax, xint, yint, ref_right, dir_right, r, col_R, names{2});

end


function ang_deg = draw_one_theta_arc(ax, xint, yint, vert, dirv, r, color, name)
if nargin < 8, name = ''; end
% Draw one small arc from 'vert' to 'dirv' at (xint,yint), radius r, and
% label it with the swept angle in degrees (also returned).
theta1 = atan2(vert(2), vert(1));
theta2 = atan2(dirv(2), dirv(1));
dtheta = mod(theta2 - theta1 + pi, 2*pi) - pi; % shortest signed sweep
ang_deg = abs(rad2deg(dtheta));

thetas = theta1 + linspace(0, dtheta, 30);
arc_x = xint + r*cos(thetas);
arc_y = yint + r*sin(thetas);
plot(ax, arc_x, arc_y, '-', 'Color', color, 'LineWidth', 1.5, 'HandleVisibility', 'off');

mid_theta = theta1 + dtheta/2;
lr = 1.25;
if ~isempty(name), lr = 1.8; end   % symbol labels are larger: keep them clear of the arc
tx = xint + lr*r*cos(mid_theta);
ty = yint + lr*r*sin(mid_theta);
if isempty(name)
    text(ax, tx, ty, sprintf('%.1f%s', ang_deg, char(176)), 'Color', color, ...
        'FontWeight', 'bold', 'FontSize', 8, 'HorizontalAlignment', 'center');
    return;
end
text(ax, tx, ty, name, 'Color', color, 'Interpreter', 'latex', ...
    'FontSize', 15, 'HorizontalAlignment', 'center');

end
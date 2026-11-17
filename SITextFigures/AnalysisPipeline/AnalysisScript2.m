img1 = imread("DSC_0505.jpg (red).png");
im2 =imread("DSC_0585.jpg (red).png");
% img1 = imread("DSC_0518.jpg");
% im2 = imread("DSC_0558.jpg");
im3= imread("DSC_0660.jpg (red).png");
%im4= imread("DSC_0257 (red).jpg");
ppmmx = 39.16;
ppmmy = 39.8;


try
load("thirtymicronpeaks.mat");
catch
   %im3_peaks = peak_selector(im3);
   %im4_peaks = peak_selector(im4);
    img1_peaks = peak_selector(img1);
    im2_peaks = peak_selector(im2);
 %combined_peaks = [im2_peaks];
    combined_peaks = [img1_peaks,im2_peaks,im3_peaks];
    % combined_peaks = [img1_peaks,im3_peaks];%,im3_peaks];%,im4_peaks];
    save("thirtymicronpeaks_tests.mat","combined_peaks")
end
peak_heights = [];
peak_angles_info = [];
for i = 6:6
pixel_peak_height = heights(combined_peaks(i));
peak_heights = [peak_heights;pixel_peak_height];
peak_angle = angle_finder(combined_peaks(i),ppmmx,ppmmy);
peak_angles_info = [peak_angles_info,peak_angle];
end


save("thirtymicronpeaks_heights2__2.mat","peak_heights","ppmmy","ppmmx")
save("thirtymicronpeaks_angles2__2.mat","peak_angles_info")




function height_calculation = heights(peak)
% Expecting 'peak' to be a struct with fields 'img' (RGB crop) and 'coords' (original image coords)
if isempty(peak) || ~isstruct(peak) || isempty(peak.img)
    height_calculation = NaN;
    return;
end

crop = peak.img;
if size(crop,3) < 3
    % if grayscale, treat as single channel
    red = im2double(crop(:,:,1));
else
    red = im2double(crop(:,:,1)); % use red channel
end

hFig = figure('Name','Define baseline: draw a line across baseline and double-click to finish','NumberTitle','off');
imshow(red,[]); colormap(gca,gray);
title('Draw baseline with imline (double-click to finish).');
hLine = imline;
pos = wait(hLine); % [x1 y1; x2 y2]
close(hFig);

if isempty(pos) || any(isnan(pos(:))) || size(pos,1)~=2
    height_calculation = NaN;
    return;
end

% Compute baseline line in image coords of the crop
x1 = pos(1,1); y1 = pos(1,2);
x2 = pos(2,1); y2 = pos(2,2);
% Prompt user to click the peak point within the crop to get px, py (crop-local coords)
hFigPts = figure('Name','Click peak point on crop','NumberTitle','off');
imshow(red,[]); colormap(gca,gray);
%title('Click the peak point (single click).');
[xp, yp] = ginput(1);
close(hFigPts);

if isempty(xp) || isempty(yp) || any(isnan([xp yp]))
    height_calculation = NaN;
    return;
end

% Use clicked coordinates as px, py in crop-local coordinates
px = xp;
py = yp;
% Convert peak coords (original image) to crop-local coords
% Need to know crop offset: infer from peak.coords stored as original image coords.
% Assume peak.coords refer to original image and crop was created at some r during selection.
% If peak contains no offset info, assume the peak point is within crop and map by centering:
% Here we check for optional fields 'crop_origin' else try to compute by locating brightest approx location.


% Project peak point onto baseline (in crop coords)
% Line param t for projection
dx = x2 - x1; dy = y2 - y1;
slope = dy/dx;
y_at_px = y1 + slope*(px-x1);
height_px = py-y_at_px;

% Return signed height (pixels)
height_calculation = height_px;
end


function peaks = peak_selector(img)
% Allow multiple ROIs: user draws rectangular ROIs sequentially.
% Instructions: draw rectangle with mouse (double-click or press Enter to finish each),
% press Enter with no rectangle to finish all ROIs.
hFig = figure('Name','Select multiple ROIs: draw rectangle for each peak. Press Enter when done','NumberTitle','off');
imshow(img);
title('Draw ROI for a peak (double-click to finish rectangle). Press Enter with no rectangle to finish all ROIs.');
roiRects = []; % [x y w h] in image coords
while true
    h = imrect;
    if isempty(h) || ~isvalid(h)
        break;
    end
    pos = wait(h); % [x y w h]
    delete(h);
    if isempty(pos) || any(isnan(pos))
        break;
    end
    % Round and clamp
    [H,W,~] = size(img);
    x = round(max(1,min(W,pos(1))));
    y = round(max(1,min(H,pos(2))));
    w = round(max(1,min(W-x+1,pos(3))));
    hgt = round(max(1,min(H-y+1,pos(4))));
    roiRects(end+1,:) = [x y w hgt]; %#ok<AGROW>
    % Visual feedback
    rectangle('Position',[x y w hgt],'EdgeColor','r','LineWidth',1.5);
    drawnow;
    % Ask if user wants to add more or finish early:
    choice = questdlg('Add another ROI?','Continue','Yes','No','Yes');
    if strcmp(choice,'No')
        break;
    end
end
close(hFig);

% If no ROIs selected, return empty peaks struct
if isempty(roiRects)
    peaks = struct('coords',[],'img',[]);
    return;
end
n = size(roiRects,1);
peaks(n) = struct('img',[]); 
for k = 1:n
    r = roiRects(k,:);
    crop = img(r(2):r(2)+r(4)-1, r(1):r(1)+r(3)-1, :);
    peaks(k).img = crop;
    end% prealloc struct array
end

function angle_information = angle_finder(peak,ppmmx,ppmmy)

% ---- Default/fallback output so the function always returns something
% valid even on early exits (e.g. user cancels the click). ----
angle_information = struct( ...
    'p_left', NaN(1,4), ...
    'p_right', NaN(1,4), ...
    'angle_deg', NaN, ...
    'intersection_pt_mm', [], ...
    'left', struct('x_mm',[],'y_mm',[],'xfit_mm',[],'yfit_mm',[], ...
                    'top_pos',[],'bot_pos',[],'mean_pos',[]), ...
    'right', struct('x_mm',[],'y_mm',[],'xfit_mm',[],'yfit_mm',[], ...
                     'top_pos',[],'bot_pos',[],'mean_pos',[]) );

crop = peak.img;
[H,W,~] = size(crop); % define W (and H) since it was removed

% Show image and ask user to click the peak position (x coordinate)
hF = figure('Name','Click peak to split image (single click)','NumberTitle','off');
imshow(crop);
title('Click the peak position (single click). The image will be split vertically at that x.');
[xp, ~] = ginput(1);
close(hF);

if isempty(xp) || isnan(xp)
    return;
end

% Ensure integer column index within bounds
split_x = round(max(1, min(W, xp)));

% Split image into left and right parts at split_x.
% Include split column in left part (so left: 1:split_x, right: split_x+1:W)
left_img = crop(:, 1:split_x, :);
if split_x < W
    right_img = crop(:, split_x+1:W, :);
else
    right_img = uint8([]); % empty if no right part
end

% Store results in base workspace for further use/inspection
assignin('base', 'angle_finder_left', left_img);
assignin('base', 'angle_finder_right', right_img);
assignin('base', 'angle_finder_split_x', split_x);

% Local storage so the left- and right-half profiles both survive the loop
% (top_pos/bot_pos/mean_pos get overwritten each iteration otherwise).
profile_left_top = [];  profile_left_bot = [];  profile_left_mean = [];
profile_right_top = []; profile_right_bot = []; profile_right_mean = [];

% Process left and right halves (if right is empty, process only left)
halves = {'left','right'};
for hi = 1:2
    if hi==1
        part = left_img;
        name = 'left';
    else
        part = right_img;
        name = 'right';
    end
    if isempty(part)
        continue;
    end
    % Use red channel as double
    if size(part,3) >= 3
        R = im2double(part(:,:,1));
    else
        R = im2double(part(:,:,1));
    end
    [hrows, hcols] = size(R);
    top_pos = nan(1,hcols);
    bot_pos = nan(1,hcols);
    threshold = graythresh(R(:)); % Otsu threshold from 0-1
    bw = R > threshold; % binary bright mask
    for c = 1:hcols
        col = bw(:,c);
        idx = find(col);
        if isempty(idx)
            continue;
        end
        top_pos(c) = idx(1);           % first bright pixel (top-most row index)
        bot_pos(c) = idx(end);         % last bright pixel (bottom-most row index)
    end
    mean_pos = nanmean([top_pos; bot_pos],1);
    % (both halves are plotted together on the full crop after this loop)
    % Assign results to base workspace for further analysis
    assignin('base', sprintf('angle_%s_top',name), top_pos);
    assignin('base', sprintf('angle_%s_bot',name), bot_pos);
    assignin('base', sprintf('angle_%s_mean',name), mean_pos);

    % Keep a local copy tied to this half so it isn't clobbered next iteration
    if hi==1
        profile_left_top = top_pos;
        profile_left_bot = bot_pos;
        profile_left_mean = mean_pos;
    else
        profile_right_top = top_pos;
        profile_right_bot = bot_pos;
        profile_right_mean = mean_pos;
    end
end

% Plot the whole crop with both halves' top, bottom and mean positions on it.
% Right-half columns are shifted by split_x so they sit where they are in the crop.
Rfull = im2double(crop(:,:,1));   % red channel, as used for each half
hfig = figure('Name','Top/bottom/mean positions (both halves)','NumberTitle','off');
imshow(Rfull,[]); colormap(gca,gray); hold on;
half_x    = {1:numel(profile_left_top), split_x + (1:numel(profile_right_top))};
half_top  = {profile_left_top,  profile_right_top};
half_bot  = {profile_left_bot,  profile_right_bot};
half_mean = {profile_left_mean, profile_right_mean};
for hi = 1:2
    if isempty(half_top{hi})
        continue;   % e.g. no right half when the click was at the right edge
    end
    x = half_x{hi};
    validTop  = ~isnan(half_top{hi});
    validBot  = ~isnan(half_bot{hi});
    validMean = ~isnan(half_mean{hi});
    plot(x(validTop),  half_top{hi}(validTop),   'g.', 'MarkerSize', 6);   % top in green
    plot(x(validBot),  half_bot{hi}(validBot),   'r.', 'MarkerSize', 6);   % bottom in red
    plot(x(validMean), half_mean{hi}(validMean), 'b-', 'LineWidth', 1);    % mean in blue
end
%plot([split_x split_x] + 0.5, [0.5 H + 0.5], 'y--', 'LineWidth', 1);      % where the crop was split
%title('Both halves (green=top, red=bottom, blue=mean, yellow dashed=split)');
hold off;
% Extract profiles: for left half use left mean, take leftmost (smallest x) valid point per column set -> we want edge profile along columns.
% Retrieve mean profiles saved in base workspace
left_mean = evalin('base','angle_left_mean');
right_mean = evalin('base','angle_right_mean');


% Left edge: take columns where mean is not NaN. x positions are column centers 1..numel(left_mean)
xl_pix = find(~isnan(left_mean));
yl_pix = left_mean(xl_pix);

% Convert to mm (x divide by ppmmx, y divide by ppmmy) as requested
xl_mm = xl_pix ./ ppmmx;
yl_mm = yl_pix ./ ppmmy;

% Fit 5th order polynomial to left edge (in mm)
deg = 5;
if numel(xl_mm) >= (deg+1)
    p_left = polyfit(xl_mm, yl_mm, deg);
    % store fit and domain in base workspace
    assignin('base','p_left_poly5',p_left);
    assignin('base','xl_mm',xl_mm);
    assignin('base','yl_mm',yl_mm);
    % compute fitted curve for plotting/storage
    xfitl = linspace(min(xl_mm), max(xl_mm), 200);
    yfitl = polyval(p_left, xfitl);
    assignin('base','xfitl_mm',xfitl);
    assignin('base','yfitl_mm',yfitl);
else
    warning('Not enough valid points to fit %dth order polynomial for left half.', deg);
    p_left = NaN(1,deg+1);
    assignin('base','p_left_poly5',p_left);
end

% Right edge: columns relative to right half; x positions should account for split_x offset.
right_mean = right_mean; % already loaded
xr_pix_rel = find(~isnan(right_mean));
yr_pix = right_mean(xr_pix_rel);

% Convert right-side x to absolute column positions in crop: split_x was stored
if evalin('base','exist(''angle_finder_split_x'',''var'')')
    split_x = evalin('base','angle_finder_split_x');
else
    split_x = 0;
end
% Absolute pixel x positions: columns in right half start at split_x+1
xr_pix = split_x + xr_pix_rel;

% Convert to mm
xr_mm = (xr_pix) ./ ppmmx;
yr_mm = (yr_pix) ./ ppmmy;

% Fit 5th order polynomial to right edge (in mm)
if numel(xr_mm) >= (deg+1)
    p_right = polyfit(xr_mm, yr_mm, deg);
    assignin('base','p_right_poly5',p_right);
    assignin('base','xr_mm',xr_mm);
    assignin('base','yr_mm',yr_mm);
    xfitr = linspace(min(xr_mm), max(xr_mm), 200);
    yfitr = polyval(p_right, xfitr);
    assignin('base','xfitr_mm',xfitr);
    assignin('base','yfitr_mm',yfitr);
else
    warning('Not enough valid points to fit %dth order polynomial for right half.', deg);
    p_right = NaN(1,deg+1);
    assignin('base','p_right_poly5',p_right);
end

% Optionally plot combined fits over original crop in mm coordinates (store figure handle)
try
    fh = figure('Name','Polynomial fits (mm)','NumberTitle','off');
    hold on;
    % display raw points
    plot(xl_mm, yl_mm, 'bo');
    plot(xr_mm, yr_mm, 'ro');
    if exist('xfitl','var')
        plot(xfitl, yfitl, 'b-','LineWidth',1.5);
    end
    if exist('xfitr','var')
        plot(xfitr, yfitr, 'r-','LineWidth',1.5);
    end
    xlabel('x (mm)'); ylabel('y (mm)');
    legend({'left pts','right pts','left fit','right fit'}, 'Location','best');
    hold off;
    assignin('base','angle_fit_fig',fh);
catch
    % ignore plotting errors
end
% Compute intersection point of left and right polynomial fits (in mm) and angle between tangents
intersection_pt_mm = [];
angle_deg = NaN;

if all(isfinite(p_left)) && all(isfinite(p_right))
    % Form polynomial for difference p_left(x) - p_right(x) = 0
    pdiff = polysubtract(p_left, p_right); % requires Signal Processing Toolbox? implement fallback
    if isempty(pdiff)
        % fallback manual subtraction
        % pad to same length
        L = max(numel(p_left), numel(p_right));
        a = [zeros(1,L-numel(p_left)), p_left];
        b = [zeros(1,L-numel(p_right)), p_right];
        pdiff = a - b;
    end
    % Find real roots of pdiff
    r = roots(pdiff);
    r = r(imag(r)==0); % real roots only
    if ~isempty(r)
        % choose intersection within overlapping x-range of data
        xmin = max(min(xl_mm), min(xr_mm));
        xmax = min(max(xl_mm), max(xr_mm));
        r_valid = r(r >= xmin-1e-6 & r <= xmax+1e-6);
        if isempty(r_valid)
            r_valid = r; % if none in overlap, take any real root
        end
        xint = r_valid(1);
        yint = polyval(p_left, xint);
        intersection_pt_mm = [xint, yint];
        assignin('base','angle_intersection_mm',intersection_pt_mm);
        % compute derivatives (slopes) of polynomials at intersection
        dp_left = polyder(p_left);
        dp_right = polyder(p_right);
        m1 = polyval(dp_left, xint);
        m2 = polyval(dp_right, xint);
        % angle between two lines with slopes m1,m2
        angle_rad = atan(abs((m2 - m1) / (1 + m1*m2)));
        angle_deg = rad2deg(angle_rad);
        assignin('base','angle_between_halves_deg',angle_deg);
    else
        warning('No real intersection found between left and right polynomials.');
    end
else
    warning('Polynomial fits for left and/or right are not available.');
end

% Plot intersection and tangents on previous fit figure if available
if ~isempty(intersection_pt_mm) && exist('fh','var') && ishghandle(fh)
    figure(fh); hold on;
    %plot(intersection_pt_mm(1), intersection_pt_mm(2), 'kp','MarkerSize',12,'MarkerFaceColor','y');
    % plot tangent lines at intersection (short segments)
    Lseg = (max([xl_mm(:); xr_mm(:)]) - min([xl_mm(:); xr_mm(:)])) * 0.1;
    xseg = linspace(intersection_pt_mm(1)-Lseg, intersection_pt_mm(1)+Lseg, 50);
    yseg1 = polyval(p_left, intersection_pt_mm(1)) + polyval(dp_left, intersection_pt_mm(1)).*(xseg - intersection_pt_mm(1));
    yseg2 = polyval(p_right, intersection_pt_mm(1)) + polyval(dp_right, intersection_pt_mm(1)).*(xseg - intersection_pt_mm(1));
   % plot(xseg, yseg1, 'b--', 'LineWidth',1);
   % plot(xseg, yseg2, 'r--', 'LineWidth',1);
   % legend({'left pts','right pts','left fit','right fit','intersection','tangent left','tangent right'}, 'Location','best');
    hold off;
end

% ---- Package everything into the return value ----
angle_information.p_left = p_left;
angle_information.p_right = p_right;
angle_information.angle_deg = angle_deg;
angle_information.intersection_pt_mm = intersection_pt_mm;

angle_information.left.x_mm = xl_mm;
angle_information.left.y_mm = yl_mm;
angle_information.left.top_pos = profile_left_top;
angle_information.left.bot_pos = profile_left_bot;
angle_information.left.mean_pos = profile_left_mean;
if exist('xfitl','var')
    angle_information.left.xfit_mm = xfitl;
    angle_information.left.yfit_mm = yfitl;
else
    angle_information.left.xfit_mm = [];
    angle_information.left.yfit_mm = [];
end

angle_information.right.x_mm = xr_mm;
angle_information.right.y_mm = yr_mm;
angle_information.right.top_pos = profile_right_top;
angle_information.right.bot_pos = profile_right_bot;
angle_information.right.mean_pos = profile_right_mean;
if exist('xfitr','var')
    angle_information.right.xfit_mm = xfitr;
    angle_information.right.yfit_mm = yfitr;
else
    angle_information.right.xfit_mm = [];
    angle_information.right.yfit_mm = [];
end

end

function pdiff = polysubtract(p_left, p_right)
% p_left, p_right: row vectors of polynomial coefficients (highest-degree first)

% ensure row vectors
p_left  = p_left(:).';
p_right = p_right(:).';

% pad to equal length
nL = numel(p_left); nR = numel(p_right);
if nL < nR
    p_left = [zeros(1,nR-nL), p_left];
elseif nR < nL
    p_right = [zeros(1,nL-nR), p_right];
end

% subtract and trim leading zeros (leave single zero for zero polynomial)
pdiff = p_left - p_right;
nz = find(pdiff~=0, 1, 'first');
if isempty(nz)
    pdiff = 0;
else
    pdiff = pdiff(nz:end);
end
end
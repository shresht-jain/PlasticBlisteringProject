clear; close all;
filename = 'DelaminationResults.csv';
TestResults = readtable(filename);
elastomer = strtrim(string(TestResults.Elastomer));   % strtrim guards against stray spaces breaking key matches
thickness = toNumeric(TestResults.Thickness_Sandwich);
theta   = toNumeric(TestResults.one_minus_cos_theta_over_Ky_times_h);
theta_err  = toNumeric(TestResults.err_one_minus_cos_theta_over_Ky_times_h);
kappa   = toNumeric(TestResults.kappa);
kappa_err  = toNumeric(TestResults.err_kappa);
predicted_values  = toNumeric(TestResults.predictedvalue);
err_predicted_values   = toNumeric(TestResults.err_predicted);
valid = ~(isnan(theta) | isnan(theta_err) | isnan(kappa) | isnan(kappa_err));
elastomer = elastomer(valid);
thickness = thickness(valid);
theta = theta(valid);  theta_err = theta_err(valid);
kappa = kappa(valid);  kappa_err = kappa_err(valid);
predicted_values  = predicted_values(valid);
err_predicted_values   = err_predicted_values(valid);

%% ---- Plotting Colours and Thicknesses ---------------------------------------------
% Add or edit entries here to match your material names
colourMap = containers.Map( ...
    {'Pink',            'Green',           'PDMS'}, ...
    {[242/255,107/255,139/255],  [0.360784313725490	0.737254901960784	0.388235294117647],  [0.423529411764706	0.384313725490196	0.427450980392157]});
fallbackColours = lines(10);

% Display names for the legend (keys = exactly what is in the CSV's Elastomer column)
labelMap = containers.Map( ...
    {'Pink',          'Green',         'PDMS'}, ...
    {'PVS: 370 kPa',  'PVS: 830 kPa',  'PDMS: 1750 kPa'});

%% ---- Marker per thickness ---------------------------------------------
markerList = {'o','s','^','d','v','>','<','p','h'};
uThick = unique(thickness);                 % sorted ascending
uElast = unique(elastomer, 'stable');       % order of appearance in file

getColour = @(name) ...
    ternary(isKey(colourMap, char(name)), ...
            @() colourMap(char(name)), ...
            @() fallbackColours(mod(find(uElast == name) - 1, 10) + 1, :));

getLabel = @(name) ...
    ternary(isKey(labelMap, char(name)), ...
            @() string(labelMap(char(name))), ...
            @() string(name));

%% ---- Appearance settings ----------------------------------------------
markerAlpha = 0.5;    % marker face transparency (0 = invisible, 1 = opaque)
edgeAlpha   = 0.8;    % marker edge transparency
fs          = 14;            % font size used for axes, labels, legends and annotations

%% ---- Plot --------------------------------------------------------------
fig = figure('Color', 'w', 'Position', [100 100 760 560]);
ax = axes(fig); hold(ax, 'on'); box(ax, 'on');
ax.Position = [0.10 0.13 0.86 0.80];     % axes fill the figure; both legends sit inside them

for i = 1:numel(theta)
    if ~(isfinite(theta(i)) && isfinite(kappa(i))), continue; end   % Inf: kept in data, not drawn
    col = getColour(elastomer(i));
    mk  = markerList{mod(find(uThick == thickness(i)) - 1, numel(markerList)) + 1};

    % Layer 1: black error bars only (no marker)
    errorbar(ax, kappa(i), theta(i), theta_err(i), theta_err(i), kappa_err(i), kappa_err(i), ...   % kappa on x-axis; neg/pos y err, neg/pos x err
        'LineStyle', 'none', ...
        'Marker', 'none', ...
        'Color', 'k', ...
        'LineWidth', 1.2, ...
        'CapSize', 5, ...
        'HandleVisibility', 'off');

    % Layer 2: semi-transparent markers on top
    scatter(ax, kappa(i), theta(i), 64, mk, ...      % 64 ~ MarkerSize 8 (area in pt^2)
        'MarkerFaceColor', col, ...
        'MarkerEdgeColor', 'k', ...
        'MarkerFaceAlpha', markerAlpha, ...
        'MarkerEdgeAlpha', edgeAlpha, ...
        'LineWidth', 1.0, ...
        'HandleVisibility', 'off');
end

% LabelFontSizeMultiplier = 1 stops MATLAB scaling the axis labels to 1.1 x fs
set(ax, 'FontSize', fs, 'LabelFontSizeMultiplier', 1, 'TitleFontSizeMultiplier', 1);
xlabel(ax, '$\hat{\kappa}$', 'Interpreter', 'latex', 'FontSize', fs);
ylabel(ax, '$\hat{\Theta}$', 'Interpreter', 'latex', 'FontSize', fs);

% predicted = predictedValue(kappa);
% disp(table(elastomer, thickness, kappa, predicted, ...
%      'VariableNames', {'Elastomer','Thickness','kappa','Predicted'}));
%
% (b) Smooth prediction curve across the kappa range, drawn on the plot
% extends past sqrt(2), where the prediction is constantly zero
kGrid = linspace(0.9*min(kappa(kappa > 0)), max(1.05*max(kappa), 2.5), 600);
hPred = plot(ax, kGrid, predictedValue(kGrid), 'k--', 'LineWidth', 1.5);

% (c) Single shaded band from fitted envelopes (elastomer ignored)
% Upper / lower envelope data at each point (values provided in the file):
%     upper = predictedvalue + nSigma*err_predicted,  lower = predictedvalue - nSigma*err_predicted
% The prediction (1 - kappa^2/2)/(2*kappa^2) = 1/(2*kappa^2) - 1/4 has the form A/kappa^2 + B,
% so each envelope is fitted with that same form (linear least squares) and the fits are
% used as the band boundaries.
nSigma = 2;

% points where the prediction is non-zero (kappa <= sqrt(2)) and the error is available
idx = isfinite(kappa) & isfinite(predicted_values) & isfinite(err_predicted_values) & (kappa <= sqrt(2)) & (err_predicted_values > 0);
kd  = kappa(idx);
upd = predicted_values(idx) + nSigma*err_predicted_values(idx);          % upper envelope data
lod = predicted_values(idx) - nSigma*err_predicted_values(idx);          % lower envelope data

X  = [1 ./ kd.^2, ones(size(kd))];                  % basis: A/kappa^2 + B
cU = X \ upd;                                       % [A_upper; B_upper]
cL = X \ lod;                                       % [A_lower; B_lower]

% band uses the SAME kappa grid as the dashed line (up to sqrt(2)), and is centred
% exactly on the dashed line: dashed line +/- half the fitted envelope width
kG  = kGrid(kGrid <= sqrt(2));
halfWidth = ((cU(1) ./ kG.^2 + cU(2)) - (cL(1) ./ kG.^2 + cL(2))) / 2;
yHi = predictedValue(kG) + halfWidth;               % upper boundary
yLo = predictedValue(kG) - halfWidth;               % lower boundary

hBand = fill(ax, [kG, fliplr(kG)], [yLo, fliplr(yHi)], ...
    [0.5 0.5 0.5], 'FaceAlpha', 0.1, 'EdgeColor', 'none', ...
    'HandleVisibility', 'off');
uistack(hBand, 'bottom');                           % keep points on top

% dummy patch for the legend
hBandLeg = patch(ax, NaN, NaN, [0.5 0.5 0.5], 'FaceAlpha', 0.1, 'EdgeColor', 'none');

xCrit = sqrt(2);
yLim = ylim(ax);

line(ax, [xCrit xCrit], yLim, ...
    'LineStyle', ':', ...
    'LineWidth', 1.2, ...
    'Color', [0.2 0.2 0.2], ...
    'HandleVisibility', 'off');

text(ax, xCrit, yLim(2), '$\hat{\kappa}=\sqrt{2}$', ...
    'Interpreter', 'latex', ...
    'VerticalAlignment', 'top', ...
    'HorizontalAlignment', 'left', ...
    'Rotation', 0, ...
    'FontSize', fs, 'Position', [0.985809806504551, 12.80701754385965, 0]);

%% ---- Legend 1: elastomer (colour) + model curve/band, on the main axes --
hLeg1 = gobjects(0);  lbl1 = strings(0);

for k = 1:numel(uElast)
    hLeg1(end+1) = scatter(ax, NaN, NaN, 81, 's', ...
        'MarkerFaceColor', getColour(uElast(k)), 'MarkerEdgeColor', 'k', ...
        'MarkerFaceAlpha', markerAlpha, 'MarkerEdgeAlpha', edgeAlpha); %#ok<SAGROW>
    lbl1(end+1) = getLabel(uElast(k)); %#ok<SAGROW>
end
hLeg1(end+1) = hPred;     lbl1(end+1) = "Predicted";
hLeg1(end+1) = hBandLeg;  lbl1(end+1) = sprintf("Predicted \\pm %g\\sigma", nSigma);

lg1 = legend(ax, hLeg1, lbl1, 'Location', 'none', 'FontSize', fs);
lg1.Units = 'normalized';
axP    = ax.Position;                                        % axes box in figure-normalized units
p1     = lg1.Position;
margin = 0.01;
lg1.Position = [axP(1) + axP(3) - p1(3) - margin, ...        % flush with the right edge of the axes
                axP(2) + axP(4) - p1(4) - margin, ...        % flush with the top edge of the axes
                p1(3), p1(4)];

%% ---- Legend 2: thickness (marker shape), on an invisible overlay axes ---
% MATLAB allows only one legend per axes, so the second one lives on a
% transparent overlay axes.
ax2 = axes(fig, 'Position', ax.Position, 'Visible', 'off', 'HitTest', 'off');
hold(ax2, 'on');

hLeg2 = gobjects(0);  lbl2 = strings(0);
for k = 1:numel(uThick)
    mk = markerList{mod(k - 1, numel(markerList)) + 1};
    hLeg2(end+1) = scatter(ax2, NaN, NaN, 64, mk, ...
        'MarkerFaceColor', [0.8 0.8 0.8], 'MarkerEdgeColor', 'k', ...
        'MarkerFaceAlpha', markerAlpha, 'MarkerEdgeAlpha', edgeAlpha); %#ok<SAGROW>
    lbl2(end+1) = sprintf('%g', uThick(k)); %#ok<SAGROW>
end

lg2 = legend(ax2, hLeg2, lbl2, 'Location', 'none', 'FontSize', fs, 'NumColumns', 8);
lg2.Units = 'normalized';
p2 = lg2.Position;
lg2.Position = [axP(1) + axP(3) - p2(3) - margin, ...        % right-aligned with legend 1
                lg1.Position(2) - 0.02 - p2(4), ...          % directly below legend 1
                p2(3), p2(4)];

% Stacking order: the main axes has an opaque white background and would hide
% anything drawn beneath it, so make sure the overlay axes and BOTH legends are on top.
uistack(ax2, 'top');
uistack(lg1, 'top');
uistack(lg2, 'top');
set(fig, 'CurrentAxes', ax);    % NOT axes(ax): that would raise the main axes over legend 2

%% ---- Local helpers -----------------------------------------------------
function v = toNumeric(v)
    if ~isnumeric(v)
        v = str2double(string(v));   % "#DIV/0!" and other text -> NaN
    end
end

function p = predictedValue(kappa)
    % Vectorised version of =IF(AC2>0,0,(1-(AA2/2))/(2*AA2)),  AA = kappa^2
    p = zeros(size(kappa));
    m = (kappa - sqrt(2)) <= 0;
    p(m) = (1 - kappa(m).^2/2) ./ (2*kappa(m).^2);
end

function out = ternary(cond, f1, f2)
    if cond, out = f1(); else, out = f2(); end
end
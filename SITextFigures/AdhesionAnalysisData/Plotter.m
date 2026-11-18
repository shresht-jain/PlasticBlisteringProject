% replotter.m - rebuilds the combined hysteresis figure from the saved CSVs
% (no processing: just reads <colour>_raw_plotted.csv and <colour>_mean_curves.csv)
clear; close all;

base = "I:\Shresht Projects\Delamination\MAINTESTS\NewSJAdhesion";

% Plot order, colour-legend labels and colours (dark edge / light fill)
mats      = ["green", "pink", "grey"];
matLabels = containers.Map({'pink', 'green', 'grey'}, ...
                           {'PVS: 370 kPa', 'PVS: 830 kPa', 'PDMS: 1750 kPa'});
cDark  = containers.Map({'pink', 'green', 'grey'}, {[121 54 70]/255,  [46 94 50]/255,   [64 64 64]/255});
cLight = containers.Map({'pink', 'green', 'grey'}, {[248 181 197]/255, [167 215 171]/255, [127 127 127]/255});
lighten = 0.4;              % 0 = dark edge shade, 1 = light fill shade (mean curves)

fig = figure('Color', 'w', 'Position', [100 100 700 520]);
ax  = axes(fig);
hold(ax, 'on'); box(ax, 'on');

% ---------- Raw data first, then mean curves on top ----------
for m = mats
    raw = readtable(fullfile(base, m + "_raw_plotted.csv"));
    plot(ax, raw.Extension_mm, raw.Load_N, '-', ...
         'Color', 0.35*cLight(char(m)) + 0.65, 'LineWidth', 0.5);
end
for m = mats
    mc = readtable(fullfile(base, m + "_mean_curves.csv"));
    cLine = (1-lighten)*cDark(char(m)) + lighten*cLight(char(m));
    plot(ax, mc.Extension_mm, mc.MeanLoading_N,   '-',  'Color', cLine, 'LineWidth', 2.2);
    plot(ax, mc.Extension_mm, mc.MeanUnloading_N, '--', 'Color', cLine, 'LineWidth', 2.2);
end
xlabel(ax, 'Extension (mm)');
ylabel(ax, 'Load (N)');

% ---------- Legend 1: line styles ----------
h = gobjects(1, 3);
h(1) = plot(ax, NaN, NaN, '-',   'Color', [0.80 0.80 0.80], 'LineWidth', 1.5);
h(2) = plot(ax, NaN, NaN, 'k-',  'LineWidth', 2);
h(3) = plot(ax, NaN, NaN, 'k--', 'LineWidth', 2);
legend(ax, h, {'Raw data', 'Loading', 'Unloading'}, 'Location', 'northwest', 'AutoUpdate', 'off');

% ---------- Legend 2: colours (on a transparent overlay axes) ----------
order = ["pink", "green", "grey"];          % order shown in the colour legend
ax2 = axes('Parent', fig, 'Units', ax.Units, 'Position', ax.Position, 'Color', 'none', ...
           'XTick', [], 'YTick', [], 'XColor', 'none', 'YColor', 'none', 'HitTest', 'off');
hold(ax2, 'on');
p = gobjects(1, numel(order));
for i = 1:numel(order)
    p(i) = plot(ax2, NaN, NaN, 's', 'MarkerSize', 9, ...
                'MarkerFaceColor', cLight(char(order(i))), 'MarkerEdgeColor', 'k');
end
lg2 = legend(ax2, p, cellfun(@(k) matLabels(k), cellstr(order), 'UniformOutput', false), ...
             'AutoUpdate', 'off');
lg2.Units = 'normalized';
lg2.Position(1:2) = [ax.Position(1) + ax.Position(3) - lg2.Position(3) - 0.01, ax.Position(2) + 0.01];
uistack(ax2, 'top');
setappdata(fig, 'posLink', linkprop([ax ax2], 'Position'));   % keep axes aligned on resize
axes(ax);

% exportgraphics(fig, fullfile(base, 'hysteresis_all.png'), 'Resolution', 300);

figs = findobj(groot, 'Type', 'figure');
nL = arrayfun(@(f) numel(findobj(f, 'Type', 'line')), figs);
fig = figs(find(nL == max(nL), 1));            % figure with the most lines = your plot
figure(fig);
axs = findobj(fig, 'Type', 'axes');
nKids = arrayfun(@(a) numel(a.Children), axs);
ax = axs(find(nKids == max(nKids), 1));
delete(axs(axs ~= ax));
fprintf('Figure %d, data axes has %d objects, %d other axes removed\n', fig.Number, numel(ax.Children), numel(axs)-1);
matLabels = {'PVS: 370 kPa', 'PVS: 830 kPa', 'PDMS: 1750 kPa'};
matCols   = [248 181 197; 167 215 171; 127 127 127] / 255;
ax2 = axes('Parent', fig, 'Units', ax.Units, 'Position', ax.Position, 'Color', 'none', ...
           'XTick', [], 'YTick', [], 'XColor', 'none', 'YColor', 'none', 'HitTest', 'off');
hold(ax2, 'on');
p = gobjects(1, 3);
for i = 1:3, p(i) = plot(ax2, 0, 0, 's', 'MarkerSize', 9, 'MarkerFaceColor', matCols(i,:), 'MarkerEdgeColor', 'k', 'Visible', 'on'); end
set(p, 'XData', NaN, 'YData', NaN);
lg2 = legend(ax2, p, matLabels, 'AutoUpdate', 'off');
lg2.Units = 'normalized';
lg2.Position(1:2) = [ax.Position(1)+ax.Position(3)-lg2.Position(3)-0.01, ax.Position(2)+0.01];
lg2.Visible = 'on';
uistack(ax2, 'top');
fprintf('Colour legend created: %d\n', isvalid(lg2));
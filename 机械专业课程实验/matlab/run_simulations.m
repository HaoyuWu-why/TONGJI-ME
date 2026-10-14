%% Control Engineering MATLAB/Simulink laboratory
% Models reproduce the topology shown in the original blank report.
clearvars;
close all force;
clc;

rootDir = fileparts(mfilename('fullpath'));
modelDir = fullfile(rootDir, 'models');
outDir = fullfile(rootDir, 'results');
if ~exist(outDir, 'dir')
    mkdir(outDir);
end
addpath(modelDir);

results.environment.matlabVersion = version;
results.environment.solver = 'ode4 fixed-step';
results.environment.runDate = datestr(now, 31);

models = {'orig_exp_p', 'orig_exp_i', 'orig_exp_first_order', ...
    'orig_exp_pid', 'orig_exp_second_order', 'orig_exp_frequency', ...
    'orig_exp_linear', 'orig_exp3_series', 'orig_exp3_feedback', ...
    'orig_exp3_compound'};
for k = 1:numel(models)
    open_system(models{k});
end

%% Export the actual Simulink block diagrams
exportModel('orig_exp_p', 'model_proportional_original.png');
exportModel('orig_exp_i', 'model_integral_original.png');
exportModel('orig_exp_first_order', 'model_first_order_original.png');
exportModel('orig_exp_pid', 'model_pid_original.png');
exportModel('orig_exp_second_order', 'model_second_order_original.png');
exportModel('orig_exp_frequency', 'model_frequency_original.png');
exportModel('orig_exp_linear', 'model_linear_original.png');
exportModel('orig_exp3_series', 'model_series_original.png');
exportModel('orig_exp3_feedback', 'model_feedback_original.png');
exportModel('orig_exp3_compound', 'model_compound_original.png');

%% Experiment 1: proportional element, K = 5, 10, 20
[out, t, y] = runLogged('orig_exp_p', 'P_ScopeData', '0.001', '10');
results.proportional.finalValues = mean(y(t >= 9.5, :), 1);
results.proportional.sampleCount = numel(t);
writeData(fullfile(outDir, 'data_proportional.csv'), t, y);
exportScope('orig_exp_p', '6', 'scope_proportional_original.png', ...
    'Proportional element: K = 5, 10, 20', '10');
clear out;

%% Experiment 1: integral element, T = 1, 5, 50 s
[out, t, y] = runLogged('orig_exp_i', 'I_ScopeData', '0.001', '10');
fitMask = t >= 2;
results.integral.measuredSlopes = zeros(1, size(y, 2));
for k = 1:size(y, 2)
    p = polyfit(t(fitMask), y(fitMask, k), 1);
    results.integral.measuredSlopes(k) = p(1);
end
writeData(fullfile(outDir, 'data_integral.csv'), t, y);
exportScope('orig_exp_i', '6', 'scope_integral_original.png', ...
    'Integral element: T = 1, 5, 50 s', '10');
clear out;

%% Experiment 1: first-order elements, exactly five branches from the report
[out, t, y] = runLogged('orig_exp_first_order', 'FirstOrder_ScopeData', '0.0001', '10');
timeConstants = [0.01 0.1 0.5 1 5];
results.firstOrder.timeConstants = timeConstants;
results.firstOrder.t632 = zeros(size(timeConstants));
for k = 1:numel(timeConstants)
    idx = find(t >= 1 & y(:, k) >= 0.632, 1, 'first');
    results.firstOrder.t632(k) = t(idx) - 1;
end
writeData(fullfile(outDir, 'data_first_order.csv'), t, y);
exportScope('orig_exp_first_order', '8', 'scope_first_order_original.png', ...
    'First-order element: T = 0.01, 0.1, 0.5, 1, 5 s', '10');
clear out;

%% Experiment 1: PI, PD and PID using the original parallel P-I-D topology
kpPath = Simulink.ID.getFullName('orig_exp_pid:2');
kiPath = Simulink.ID.getFullName('orig_exp_pid:3');
kdPath = Simulink.ID.getFullName('orig_exp_pid:5');
pidCases = struct( ...
    'name', {'PI', 'PD', 'PID'}, ...
    'kp', {1, 1, 1}, ...
    'ki', {0.5, 0, 0.5}, ...
    'kd', {0, 0.0002, 0.0002}, ...
    'file', {'scope_pi_original.png', 'scope_pd_original.png', 'scope_pid_original.png'});
for k = 1:numel(pidCases)
    in = Simulink.SimulationInput('orig_exp_pid');
    in = in.setBlockParameter(kpPath, 'Gain', num2str(pidCases(k).kp));
    in = in.setBlockParameter(kiPath, 'Gain', num2str(pidCases(k).ki));
    in = in.setBlockParameter(kdPath, 'Gain', num2str(pidCases(k).kd));
    in = in.setModelParameter('SolverType', 'Fixed-step', 'Solver', 'ode4', ...
        'FixedStep', '0.0001', 'StopTime', '4', 'ReturnWorkspaceOutputs', 'on');
    out = sim(in);
    [tPid, yPid] = datasetArrays(out.get('PID_ScopeData'));
    results.pid.(pidCases(k).name).peak = max(yPid);
    results.pid.(pidCases(k).name).finalValue = yPid(end);
    writeData(fullfile(outDir, ['data_' lower(pidCases(k).name) '.csv']), tPid, yPid);
    exportScope('orig_exp_pid', '8', pidCases(k).file, ...
        sprintf('%s response: Kp=%g, Ki=%g, Kd=%g', pidCases(k).name, ...
        pidCases(k).kp, pidCases(k).ki, pidCases(k).kd), '4');
end
clear out;

%% Experiment 1: second-order closed loop using the exact factorized model
tf2Path = Simulink.ID.getFullName('orig_exp_second_order:4');
gainPath = Simulink.ID.getFullName('orig_exp_second_order:5');
zetaCases = [-1/(2*sqrt(2)) 0.001 0.3 1 1.5];
T2Cases = [-2 500 1/(2*0.3) 0.5 1/3];
KCases = [-1 500 1/(2*0.3) 0.5 1/3];
zetaFiles = {'scope_second_order_negative.png', 'scope_second_order_zero.png', ...
    'scope_second_order_underdamped.png', 'scope_second_order_critical.png', ...
    'scope_second_order_overdamped.png'};
for k = 1:numel(zetaCases)
    in = Simulink.SimulationInput('orig_exp_second_order');
    in = in.setBlockParameter(tf2Path, 'Denominator', sprintf('[%.12g 1]', T2Cases(k)));
    in = in.setBlockParameter(gainPath, 'Gain', sprintf('%.12g', KCases(k)));
    stopTime = '20';
    if zetaCases(k) < 0
        stopTime = '12';
    end
    in = in.setModelParameter('SolverType', 'Fixed-step', 'Solver', 'ode4', ...
        'FixedStep', '0.0005', 'StopTime', stopTime, 'ReturnWorkspaceOutputs', 'on');
    out = sim(in);
    [tSecond, ySecond] = datasetArrays(out.get('SecondOrder_ScopeData'));
    fieldName = sprintf('case%d', k);
    results.secondOrder.(fieldName).zeta = zetaCases(k);
    results.secondOrder.(fieldName).T1 = 1;
    results.secondOrder.(fieldName).T2 = T2Cases(k);
    results.secondOrder.(fieldName).K = KCases(k);
    results.secondOrder.(fieldName).peak = max(ySecond);
    if zetaCases(k) > 0.01
        results.secondOrder.(fieldName).stepInfo = stepinfo(ySecond, tSecond, 1);
    end
    writeData(fullfile(outDir, sprintf('data_second_order_%d.csv', k)), tSecond, ySecond);
    if zetaCases(k) == 0.001
        titleText = 'Second-order response: zeta approximately 0';
    else
        titleText = sprintf('Second-order response: zeta = %.3g', zetaCases(k));
    end
    exportScope('orig_exp_second_order', '6', zetaFiles{k}, titleText, stopTime);
end
clear out;

%% Experiment 2: frequency sweep using the original Signal Generator model
peakFrequencies = [0.66 0.68 0.69 0.70 0.705 0.707 0.710];
cutoffFrequencies = [1.260 1.268 1.270 1.272 1.274 1.276 1.280];
peakSweep = sweepFrequency(peakFrequencies);
cutoffSweep = sweepFrequency(cutoffFrequencies);
[~, peakIndex] = max(peakSweep(:, 4));
[~, cutoffIndex] = min(abs(cutoffSweep(:, 4) - 1/sqrt(2)));
results.frequency.peakSweep = peakSweep;
results.frequency.cutoffSweep = cutoffSweep;
results.frequency.wrMeasured = peakSweep(peakIndex, 1);
results.frequency.wbMeasured = cutoffSweep(cutoffIndex, 1);
results.frequency.wrTheory = sqrt(1 - 2*0.5^2);
results.frequency.wbTheory = sqrt(1 - 2*0.5^2 + sqrt(2 - 4*0.5^2 + 4*0.5^4));
results.frequency.wrErrorPercent = abs(results.frequency.wrMeasured - results.frequency.wrTheory) / results.frequency.wrTheory * 100;
results.frequency.wbErrorPercent = abs(results.frequency.wbMeasured - results.frequency.wbTheory) / results.frequency.wbTheory * 100;
writematrix(peakSweep, fullfile(outDir, 'frequency_peak_sweep.csv'));
writematrix(cutoffSweep, fullfile(outDir, 'frequency_cutoff_sweep.csv'));

runFrequencyScope(results.frequency.wrMeasured, 'scope_frequency_resonance_original.png', ...
    'Input and output at resonant frequency');
runFrequencyScope(results.frequency.wbMeasured, 'scope_frequency_cutoff_original.png', ...
    'Input and output at cutoff frequency');

%% Linearize the report's Figure 7 model at its root Inport and Outport
sysLinear = linearize('orig_exp_linear');
results.frequency.linearizedSystem = tf(sysLinear);
fig = figure('Visible', 'on', 'Position', [100 100 900 650]);
bode(sysLinear, {1e-2, 1e2});
grid on;
title('Bode diagram of the second-order closed-loop system');
drawnow;
print(fig, fullfile(outDir, 'bode_from_original_model.png'), '-dpng', '-r200');
close(fig);
fig = figure('Visible', 'on', 'Position', [100 100 900 650]);
nyquist(sysLinear);
grid on;
axis equal;
title('Nyquist diagram of the second-order closed-loop system');
drawnow;
print(fig, fullfile(outDir, 'nyquist_from_original_model.png'), '-dpng', '-r200');
close(fig);

%% Experiment 3: series lead correction
[out, t, y] = runLogged('orig_exp3_series', 'Series_ScopeData', '0.001', '8');
results.series.original = stepinfo(y(:, 1), t, 1);
results.series.corrected = stepinfo(y(:, 2), t, 1);
s = tf('s');
G0 = 10/(s*(s+1));
Gc = (0.5*s+1)/(0.08*s+1);
[~, results.series.phaseMarginOriginal, ~, results.series.crossoverOriginal] = margin(G0);
[~, results.series.phaseMarginCorrected, ~, results.series.crossoverCorrected] = margin(Gc*G0);
results.series.rampSteadyStateError = 1/dcgain(minreal(s*Gc*G0));
writeData(fullfile(outDir, 'data_series.csv'), t, y);
exportScope('orig_exp3_series', '8', 'scope_series_original.png', ...
    'Series lead correction: original and corrected responses', '8');
fig = figure('Visible', 'on', 'Position', [100 100 900 650]);
bode(G0, Gc*G0, {1e-2, 1e2});
grid on;
legend('Original open loop', 'Lead-corrected open loop', 'Location', 'southwest');
title('Bode comparison for the series lead correction');
drawnow;
print(fig, fullfile(outDir, 'bode_series_original.png'), '-dpng', '-r200');
close(fig);
clear out;

%% Experiment 3: velocity feedback correction
[out, t, y] = runLogged('orig_exp3_feedback', 'Feedback_ScopeData', '0.001', '20');
results.feedback.original = stepinfo(y(:, 1), t, 1);
results.feedback.corrected = stepinfo(y(:, 2), t, 1);
writeData(fullfile(outDir, 'data_feedback.csv'), t, y);
exportScope('orig_exp3_feedback', '9', 'scope_feedback_original.png', ...
    'Velocity feedback: original and corrected responses', '20');
clear out;

%% Experiment 3: compound correction
[out, t, y] = runLogged('orig_exp3_compound', 'Compound_ScopeData', '0.0005', '8');
results.compound.original = stepinfo(y(:, 1), t, 1);
results.compound.corrected = stepinfo(y(:, 2), t, 1);
results.compound.correctedSteadyStateError = abs(1 - y(end, 2));
writeData(fullfile(outDir, 'data_compound.csv'), t, y);
exportScope('orig_exp3_compound', '9', 'scope_compound_original.png', ...
    'Compound correction: original and corrected responses', '8');
clear out;

save(fullfile(outDir, 'original_template_results.mat'), 'results');
writeSummary(results, fullfile(outDir, 'original_template_results_summary.txt'));
disp('ORIGINAL_TEMPLATE_SIMULATION_COMPLETE');

%% Local functions
function [out, t, y] = runLogged(modelName, variableName, fixedStep, stopTime)
in = Simulink.SimulationInput(modelName);
in = in.setModelParameter('SolverType', 'Fixed-step', 'Solver', 'ode4', ...
    'FixedStep', fixedStep, 'StopTime', stopTime, 'ReturnWorkspaceOutputs', 'on');
out = sim(in);
[t, y] = datasetArrays(out.get(variableName));
end

function [t, y] = datasetArrays(ds)
values = ds{1}.Values;
t = values.Time;
y = squeeze(values.Data);
if isvector(y)
    y = y(:);
end
end

function tableData = sweepFrequency(frequencies)
tableData = zeros(numel(frequencies), 5);
sigPath = Simulink.ID.getFullName('orig_exp_frequency:1');
for n = 1:numel(frequencies)
    w = frequencies(n);
    in = Simulink.SimulationInput('orig_exp_frequency');
    in = in.setBlockParameter(sigPath, 'Frequency', num2str(w, '%.12g'));
    in = in.setModelParameter('SolverType', 'Fixed-step', 'Solver', 'ode4', ...
        'FixedStep', '0.001', 'StopTime', '90', 'ReturnWorkspaceOutputs', 'on');
    out = sim(in);
    [t, y] = datasetArrays(out.get('Frequency_ScopeData'));
    [inputAmplitude, outputAmplitude, ratio, phaseDeg] = estimateSinusoid(t, y, w);
    tableData(n, :) = [w inputAmplitude outputAmplitude ratio phaseDeg];
end
end

function runFrequencyScope(w, fileName, titleText)
sigPath = Simulink.ID.getFullName('orig_exp_frequency:1');
in = Simulink.SimulationInput('orig_exp_frequency');
in = in.setBlockParameter(sigPath, 'Frequency', num2str(w, '%.12g'));
in = in.setModelParameter('SolverType', 'Fixed-step', 'Solver', 'ode4', ...
    'FixedStep', '0.001', 'StopTime', '60', 'ReturnWorkspaceOutputs', 'on');
out = sim(in); %#ok<NASGU>
exportScope('orig_exp_frequency', '7', fileName, ...
    sprintf('%s, omega = %.3f rad/s', titleText, w), '30');
end

function [inputAmplitude, outputAmplitude, ratio, phaseDeg] = estimateSinusoid(t, y, w)
windowStart = t(end) - 4*2*pi/w;
mask = t >= windowStart;
tm = t(mask);
u = y(mask, 1);
v = y(mask, 2);
design = [sin(w*tm) cos(w*tm) ones(size(tm))];
cu = design \ u;
cv = design \ v;
inputAmplitude = hypot(cu(1), cu(2));
outputAmplitude = hypot(cv(1), cv(2));
ratio = outputAmplitude/inputAmplitude;
inputPhase = atan2(cu(2), cu(1));
outputPhase = atan2(cv(2), cv(1));
phaseDeg = rad2deg(atan2(sin(outputPhase-inputPhase), cos(outputPhase-inputPhase)));
end

function exportScope(modelName, scopeSid, fileName, titleText, timeSpan)
scopePath = Simulink.ID.getFullName([modelName ':' scopeSid]);
cfg = get_param(scopePath, 'ScopeConfiguration');
cfg.ShowLegend = true;
cfg.ShowGrid = true;
cfg.Title = titleText;
cfg.TimeSpan = timeSpan;
try
    cfg.AxesScaling = 'Auto';
catch
end
open_system(scopePath);
drawnow;
scopeName = get_param(scopePath, 'Name');
h = findall(groot, 'Type', 'figure', 'Name', scopeName);
if isempty(h)
    error('Scope window did not open for %s.', scopePath);
end
h = h(1);
h.Position = [100 100 1100 650];
h.Color = [0 0 0];
h.InvertHardcopy = 'off';
axesHandles = findall(h, 'Type', 'axes');
for axesIndex = 1:numel(axesHandles)
    axesHandles(axesIndex).Color = [0 0 0];
    axesHandles(axesIndex).XColor = [0.85 0.85 0.85];
    axesHandles(axesIndex).YColor = [0.85 0.85 0.85];
    axesHandles(axesIndex).GridColor = [0.45 0.45 0.45];
    yLimits = axesHandles(axesIndex).YLim;
    yPadding = max(0.05*(yLimits(2)-yLimits(1)), eps);
    axesHandles(axesIndex).YLim = [yLimits(1)-yPadding yLimits(2)+yPadding];
end
textHandles = findall(h, 'Type', 'text');
set(textHandles, 'Color', [0.95 0.95 0.95]);
lineHandles = findall(h, 'Type', 'line');
scopeColors = [1.00 1.00 0.00; 0.00 0.80 1.00; 1.00 0.30 0.30; ...
    0.30 1.00 0.30; 1.00 0.20 1.00];
for lineIndex = 1:numel(lineHandles)
    lineHandles(lineIndex).Color = scopeColors(1 + mod(lineIndex - 1, size(scopeColors, 1)), :);
end
drawnow;
rootDir = fileparts(mfilename('fullpath'));
print(h, fullfile(rootDir, 'results', fileName), ...
    '-dpng', '-r200');
close(h);
end

function exportModel(modelName, fileName)
open_system(modelName);
drawnow;
rootDir = fileparts(mfilename('fullpath'));
print(['-s' modelName], fullfile(rootDir, 'results', fileName), ...
    '-dpng', '-r180');
end

function writeData(fileName, t, y)
writematrix([t y], fileName);
end

function writeSummary(r, fileName)
fid = fopen(fileName, 'w');
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, 'MATLAB: %s\n', r.environment.matlabVersion);
fprintf(fid, 'Solver: %s\n', r.environment.solver);
fprintf(fid, 'Proportional final values: %.9f %.9f %.9f\n', r.proportional.finalValues);
fprintf(fid, 'Integral slopes: %.9f %.9f %.9f\n', r.integral.measuredSlopes);
fprintf(fid, 'First-order T63.2 values:');
fprintf(fid, ' %.6f', r.firstOrder.t632);
fprintf(fid, '\n');
fprintf(fid, 'PI peak/final: %.6f %.6f\n', r.pid.PI.peak, r.pid.PI.finalValue);
fprintf(fid, 'PD peak/final: %.6f %.6f\n', r.pid.PD.peak, r.pid.PD.finalValue);
fprintf(fid, 'PID peak/final: %.6f %.6f\n', r.pid.PID.peak, r.pid.PID.finalValue);
fprintf(fid, 'Frequency measured wr/wb: %.6f %.6f rad/s\n', r.frequency.wrMeasured, r.frequency.wbMeasured);
fprintf(fid, 'Frequency theory wr/wb: %.6f %.6f rad/s\n', r.frequency.wrTheory, r.frequency.wbTheory);
fprintf(fid, 'Frequency errors: %.6f%% %.6f%%\n', r.frequency.wrErrorPercent, r.frequency.wbErrorPercent);
fprintf(fid, 'Series PM: %.6f -> %.6f deg\n', r.series.phaseMarginOriginal, r.series.phaseMarginCorrected);
fprintf(fid, 'Series crossover: %.6f -> %.6f rad/s\n', r.series.crossoverOriginal, r.series.crossoverCorrected);
fprintf(fid, 'Series ramp ess: %.9f\n', r.series.rampSteadyStateError);
fprintf(fid, 'Series OS/Ts: %.6f %.6f -> %.6f %.6f\n', r.series.original.Overshoot, ...
    r.series.original.SettlingTime, r.series.corrected.Overshoot, r.series.corrected.SettlingTime);
fprintf(fid, 'Feedback OS/Ts/Tr: %.6f %.6f %.6f -> %.6f %.6f %.6f\n', ...
    r.feedback.original.Overshoot, r.feedback.original.SettlingTime, r.feedback.original.RiseTime, ...
    r.feedback.corrected.Overshoot, r.feedback.corrected.SettlingTime, r.feedback.corrected.RiseTime);
fprintf(fid, 'Compound OS/Ts/Tr: %.6f %.6f %.6f -> %.6f %.6f %.6f\n', ...
    r.compound.original.Overshoot, r.compound.original.SettlingTime, r.compound.original.RiseTime, ...
    r.compound.corrected.Overshoot, r.compound.corrected.SettlingTime, r.compound.corrected.RiseTime);
fprintf(fid, 'Compound corrected final error: %.9f\n', r.compound.correctedSteadyStateError);
end

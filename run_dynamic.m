%% run_dynamic.m - Run final_dynamic_24a with an audited Section 5.4 input
% 用法：在 MATLAB 里直接运行本脚本（F5）
% 会依次：加载物性表 -> 设置负载/反应性时序 -> 跑仿真 -> 画转速/堆功率/燃料温度
%
% The compressor candidate and the coupled Table 5.2 operating point must
% pass their independent gates before this script is used for a dynamic
% claim. A failed run is evidence of an unresolved model boundary, not a
% result to be repaired by changing the schedule.

clc;
run('start.m');            % 加载 .mat 物性表（start.m 里有 clear，所以时序变量在下方再赋值）

mdl = 'final_dynamic_24a';
if ~bdIsLoaded(mdl), load_system(mdl); end

% Set the paper design speed. This is an initial condition only; it is not
% evidence that the coupled model has reached a steady operating point.
C = paper54_constants();
set_param([mdl '/TAC/rotor/N_rpm_Integrator'], ...
    'InitialCondition', num2str(C.N_rpm, 17));

%% ===== 1. Exact Section 5.4 schedules =====
% Pload_sched is electrical output power in W_e. The matrices use eps(t)
% offsets at discontinuities; no physical delay is introduced.
S54 = paper54_schedules();
Pload_sched = S54.load.matrix;
rho_sched = S54.reactivity.matrix;

%% Optional speed perturbation setup (requires a verified steady state)
% set_param([mdl '/TAC/rotor/N_rpm_Integrator'], ...
%     'InitialCondition', num2str(1.05 * C.N_rpm, 17));
% set_param([mdl '/TAC/rotor/N_rpm_Integrator'], ...
%     'InitialCondition', num2str(0.95 * C.N_rpm, 17));

%% ===== 3. 写入工作区 =====
assignin('base','Pload_sched',Pload_sched);
assignin('base','rho_sched',rho_sched);

%% ===== 4. 跑仿真 =====
set_param(mdl, 'StopTime', num2str(S54.load.stop_time_s, 17));
simOut = sim(mdl);

%% ===== 5. 画结果 =====
N  = simOut.get('N_log');
P  = simOut.get('P_log');
Tf = simOut.get('Tf_log');

figure('Position',[80 80 900 640]);
subplot(3,1,1);
plot(N.Time, N.Data, 'b', 'LineWidth',1.2); grid on;
ylabel('转速 (rpm)'); title('TAC 转轴转速');
subplot(3,1,2);
plot(P.Time, P.Data/1e3, 'r', 'LineWidth',1.2); grid on;
ylabel('堆功率 (kWt)'); title('反应堆功率');
subplot(3,1,3);
plot(Tf.Time, Tf.Data, 'm', 'LineWidth',1.2); grid on;
ylabel('燃料温度 (K)'); xlabel('时间 (s)'); title('燃料温度');

fprintf('仿真完成，StopTime=%s s。转速末值=%.0f rpm，堆功率末值=%.1f kWt\n', ...
    get_param(mdl,'StopTime'), N.Data(end), P.Data(end)/1e3);

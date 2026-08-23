function [cp_mass, gamma, rho, miu, lambda, Pr] = HeXe_property_simulink(T, P_Pa)
% HeXe_property_simulink  He-Xe混合气体非理想物性计算
% 输入:
%   T    - 温度 (K)，标量
%   P_Pa - 压力 (Pa)，标量
%
% 输出:
%   cp_mass - 质量定压比热 (J/kg/K)
%   gamma   - 比热比 (-)
%   rho     - 密度 (kg/m^3)
%   miu     - 动力粘度 (Pa·s)
%   lambda  - 导热系数 (W/m/K)
%   Pr      - 普朗特数 (-)
%
% 物性模型:
%   密度、cp、gamma — Virial 状态方程（论文公式 2.8~2.17）
%   粘度 — Chapman-Enskog理论 + Lennard-Jones势能 + 非理想修正（论文公式 2.18~2.21）
%   导热系数 — Mason-Saxena公式 + 碰撞积分 + 非理想修正（论文公式 2.22~2.26）
%   摩尔分数: He = 71.72%, Xe = 28.28%

    %% ===== 常数定义 =====
    R0 = 8.314;
    M_He = 4.0026e-3;
    M_Xe = 131.293e-3;
    N_A = 6.02214076e23;
    k_B = R0 / N_A;
    x_He = 0.7172;
    x_Xe = 1.0 - x_He;
 
    % ===== Temperature guard (avoid complex results from sqrt/log of negative T) =====
    persistent warned_lo_hexe warned_hi_hexe
    if isempty(warned_lo_hexe), warned_lo_hexe = false; end
    if isempty(warned_hi_hexe), warned_hi_hexe = false; end
    CLAMP_LO_HeXe = 100.0;
    CLAMP_HI_HeXe = 2000.0;
    if T < CLAMP_LO_HeXe
        if ~warned_lo_hexe
            warning('HeXe:T_lo', 'T=%g K < %g K; clamping.', T, CLAMP_LO_HeXe);
            warned_lo_hexe = true;
        end
        T = CLAMP_LO_HeXe;
    elseif T > CLAMP_HI_HeXe
        if ~warned_hi_hexe
            warning('HeXe:T_hi', 'T=%g K > %g K; clamping.', T, CLAMP_HI_HeXe);
            warned_hi_hexe = true;
        end
        T = CLAMP_HI_HeXe;
    end

   M = x_Xe * M_Xe + x_He * M_He;

    T_c_He = 5.19;
    T_c_Xe = 289.6;
    rho_c_He = 69.64;
    rho_c_Xe = 1099.7;
    T_c_12 = sqrt(T_c_He * T_c_Xe);

    v_He = M_He / rho_c_He;
    v_Xe = M_Xe / rho_c_Xe;
    v_12 = (1.0/8.0) * (v_He^(1.0/3.0) + v_Xe^(1.0/3.0))^3;

    T_He = T / T_c_He;
    T_Xe = T / T_c_Xe;
    T_12 = T / T_c_12;

    %% ===== 理想气体基准值 =====
    cp0_mol = 2.5 * R0;
    cv0_mol = 1.5 * R0;

    %% ===== 二阶 Virial 系数 =====
    B11 = (8.4 - 0.0018*T + 115.0/sqrt(T) - 835.0/T) * 1e-6;
    u_Xe = 102.732 - 0.01*T_Xe - 0.44/T_Xe^1.22;
    B22 = v_Xe * (-102.6 + u_Xe * tanh(4.5*sqrt(T_Xe)));
    u_12 = 102.732 - 0.001*T_12 - 0.44/T_12^1.22;
    B12 = v_12 * (-102.6 + u_12 * tanh(4.5*sqrt(T_12)));
    B = x_He^2 * B11 + 2.0*x_He*x_Xe * B12 + x_Xe^2 * B22;

    %% ===== 三阶 Virial 系数 =====
    C111 = v_He^2 * (0.0757 + (-0.0862 - 3.6e-5*T_He + 0.0237/T_He^0.059) * tanh(0.84*T_He));
    C222 = v_Xe^2 * (0.0757 + (-0.0862 - 3.6e-5*T_Xe + 0.0237/T_Xe^0.059) * tanh(0.84*T_Xe));
    C112 = sign(C111^2 * C222) * abs(C111^2 * C222)^(1.0/3.0);
    C122 = sign(C111 * C222^2) * abs(C111 * C222^2)^(1.0/3.0);
    C = x_He^3*C111 + 3.0*x_He^2*x_Xe*C112 + 3.0*x_He*x_Xe^2*C122 + x_Xe^3*C222;

    %% ===== 求解密度 (Newton-Raphson) =====
    P_RT = P_Pa / (R0 * T);
    rho_hat = P_RT;
    for iter = 1:30
        f = C*rho_hat^3 + B*rho_hat^2 + rho_hat - P_RT;
        df = 3.0*C*rho_hat^2 + 2.0*B*rho_hat + 1.0;
        delta = f / df;
        rho_hat = rho_hat - delta;
        if abs(delta) < 1e-14
            break;
        end
    end
    rho_hat = max(rho_hat, P_RT * 0.9);
    rho = rho_hat * M;

    %% ===== Virial 系数温度导数 =====
    dB11_dT = (-0.0018 - 57.5/T^(3.0/2.0) + 835.0/T^2) * 1e-6;
    d2B11_dT2 = (86.25/T^2.5 - 1670.0/T^3) * 1e-6;

    tanh_Xe = tanh(4.5*sqrt(T_Xe));
    sech2_Xe = 1.0 - tanh_Xe^2;
    du_dT_Xe = -0.01 + 0.5368/T_Xe^2.22;
    dv_dT_Xe = 2.25/sqrt(T_Xe) * sech2_Xe;
    df_dT_Xe = du_dT_Xe * tanh_Xe + u_Xe * dv_dT_Xe;
    dB22_dT = v_Xe * df_dT_Xe / T_c_Xe;

    d2u_dT2_Xe = -1.191696/T_Xe^3.22;
    d2v_dT2_Xe = -1.125/T_Xe^1.5 * sech2_Xe - 10.125/T_Xe * sech2_Xe * tanh_Xe;
    d2f_dT2_Xe = d2u_dT2_Xe * tanh_Xe + 2.0*du_dT_Xe * dv_dT_Xe + u_Xe * d2v_dT2_Xe;
    d2B22_dT2 = v_Xe * d2f_dT2_Xe / T_c_Xe^2;

    tanh_12 = tanh(4.5*sqrt(T_12));
    sech2_12 = 1.0 - tanh_12^2;
    du_dT_12 = -0.001 + 0.5368/T_12^2.22;
    dv_dT_12 = 2.25/sqrt(T_12) * sech2_12;
    df_dT_12 = du_dT_12 * tanh_12 + u_12 * dv_dT_12;
    dB12_dT = v_12 * df_dT_12 / T_c_12;

    d2u_dT2_12 = -1.191696/T_12^3.22;
    d2v_dT2_12 = -1.125/T_12^1.5 * sech2_12 - 10.125/T_12 * sech2_12 * tanh_12;
    d2f_dT2_12 = d2u_dT2_12 * tanh_12 + 2.0*du_dT_12 * dv_dT_12 + u_12 * d2v_dT2_12;
    d2B12_dT2 = v_12 * d2f_dT2_12 / T_c_12^2;

    dB_dT = x_He^2 * dB11_dT + 2.0*x_He*x_Xe * dB12_dT + x_Xe^2 * dB22_dT;
    d2B_dT2 = x_He^2 * d2B11_dT2 + 2.0*x_He*x_Xe * d2B12_dT2 + x_Xe^2 * d2B22_dT2;

    %% ===== C 系数导数 =====
    tanh_C_He = tanh(0.84*T_He);
    sech2_C_He = 1.0 - tanh_C_He^2;
    u_C_He = -0.0862 - 3.6e-5*T_He + 0.0237/T_He^0.059;
    du_C_dT_He = -3.6e-5 - 0.0013983/T_He^1.059;
    dv_C_dT_He = 0.84 * sech2_C_He;
    dg_dT_He = du_C_dT_He * tanh_C_He + u_C_He * dv_C_dT_He;
    dC111_dT = v_He^2 * dg_dT_He / T_c_He;

    tanh_C_Xe = tanh(0.84*T_Xe);
    sech2_C_Xe = 1.0 - tanh_C_Xe^2;
    u_C_Xe = -0.0862 - 3.6e-5*T_Xe + 0.0237/T_Xe^0.059;
    du_C_dT_Xe = -3.6e-5 - 0.0013983/T_Xe^1.059;
    dv_C_dT_Xe = 0.84 * sech2_C_Xe;
    dg_dT_Xe = du_C_dT_Xe * tanh_C_Xe + u_C_Xe * dv_C_dT_Xe;
    dC222_dT = v_Xe^2 * dg_dT_Xe / T_c_Xe;

    a_coef = dC111_dT / C111;
    b_coef = dC222_dT / C222;
    dC112_dT = C112 * ((2.0/3.0)*a_coef + (1.0/3.0)*b_coef);
    dC122_dT = C122 * ((1.0/3.0)*a_coef + (2.0/3.0)*b_coef);
    dC_dT = x_He^3*dC111_dT + 3.0*x_He^2*x_Xe*dC112_dT + 3.0*x_He*x_Xe^2*dC122_dT + x_Xe^3*dC222_dT;

    a2_He = 0.0014808/T_He^2.059;
    d2g_dT_He = a2_He * tanh_C_He + 2.0*du_C_dT_He * dv_C_dT_He + u_C_He * (-1.4112 * sech2_C_He * tanh_C_He);
    d2C111_dT2 = v_He^2 * d2g_dT_He / T_c_He^2;

    a2_Xe = 0.0014808/T_Xe^2.059;
    d2g_dT_Xe = a2_Xe * tanh_C_Xe + 2.0*du_C_dT_Xe * dv_C_dT_Xe + u_C_Xe * (-1.4112 * sech2_C_Xe * tanh_C_Xe);
    d2C222_dT2 = v_Xe^2 * d2g_dT_Xe / T_c_Xe^2;

    %% ===== 修正: C112/C122 二阶导数 =====
    % 原代码(错误): a_a2 = a2_He - a_coef^2;
    % 修正后(正确): a_a2 = d2C111_dT2 / C111 - a_coef^2;
    % 原因: a_a2 = da_coef/dT, 由商法则:
    %   da_coef/dT = d/dT[dC111/dT / C111] = d2C111/dT2/C111 - (dC111/dT/C111)^2
    %             = d2C111/dT2/C111 - a_coef^2
    a_a2 = d2C111_dT2 / C111 - a_coef^2;
    b_b2 = d2C222_dT2 / C222 - b_coef^2;
    d2C112_dT2 = C112 * ((2.0/3.0)*a_a2 + (1.0/3.0)*b_b2 + ((2.0/3.0)*a_coef + (1.0/3.0)*b_coef)^2);
    d2C122_dT2 = C122 * ((1.0/3.0)*a_a2 + (2.0/3.0)*b_b2 + ((1.0/3.0)*a_coef + (2.0/3.0)*b_coef)^2);
    d2C_dT2 = x_He^3*d2C111_dT2 + 3.0*x_He^2*x_Xe*d2C112_dT2 + 3.0*x_He*x_Xe^2*d2C122_dT2 + x_Xe^3*d2C222_dT2;

    %% ===== drho_hat/dT (公式 2.16) =====
    a_rho = (rho_hat + B*rho_hat^2 + C*rho_hat^3)/T + dB_dT*rho_hat^2 + dC_dT*rho_hat^3;
    b_rho = 1.0 + 2.0*B*rho_hat + 3.0*C*rho_hat^2;
    drho_hat_dT = -a_rho / b_rho;

    %% ===== cv (公式 2.17) =====
    term1_cv = 2.0*dB_dT + T*d2B_dT2;
    term2_cv = dC_dT + 0.5*T*d2C_dT2;
    cv_mol = cv0_mol - rho_hat * R0 * T * (term1_cv + rho_hat * term2_cv);

    %% ===== cp (公式 2.15) =====
    B_1 = B - T*dB_dT;
    B_2 = B_1 - T^2 * d2B_dT2;
    C_1 = 2.0*C - T*dC_dT;
    C_2 = C - 0.5 * T^2 * d2C_dT2;
    part2 = rho_hat * R0 * (B_2 + rho_hat * C_2);
    part3 = R0 * T * (B_1 + rho_hat * C_1) * drho_hat_dT;
    cp_mol = cp0_mol + part2 + part3;

    cp_mass = cp_mol / M;
    gamma = cp_mol / cv_mol;

    %% ===== 纯组分理想气体粘度 (NIST 多项式拟合) =====
    logT = log(T);
    log_miu_He = -11.614 + 2.103*logT - 0.1473*logT^2;
    miu_He_ideal = exp(log_miu_He) * 1e-3;  % Pa·s

    log_miu_Xe = -12.450 + 2.451*logT - 0.1786*logT^2;
    miu_Xe_ideal = exp(log_miu_Xe) * 1e-3;  % Pa·s

    %% ===== Lennard-Jones 势能参数 (Chapman-Enskog理论) =====
    sigma_He = 2.576e-10;   % m, He 碰撞直径
    sigma_Xe = 4.047e-10;   % m, Xe 碰撞直径
    eps_k_He = 10.22;       % K, He 势能参数/k_B
    eps_k_Xe = 231.0;       % K, Xe 势能参数/k_B

    sigma_12 = 0.5 * (sigma_He + sigma_Xe);           % m
    eps_k_12 = sqrt(eps_k_He * eps_k_Xe);               % K
    T_star_12 = T / eps_k_12;                           % 对比温度

    %% ===== 碰撞积分 (Neufeld et al. 1972 关联式) =====
    Omega_11 = 1.0548 / T_star_12^0.15597 ...
             + 0.46736 / exp(0.58926 * T_star_12) ...
             + 1.7407 / exp(2.3489 * T_star_12);
    Omega_22 = 1.16145 / T_star_12^0.14874 ...
             + 0.52487 / exp(0.77320 * T_star_12) ...
             + 2.16178 / exp(2.43787 * T_star_12);
    Omega_12_cs = 0.84462 / T_star_12^0.19762 ...
                + 0.27875 / exp(0.42353 * T_star_12) ...
                + 1.6455 / exp(2.1666 * T_star_12);
    Omega_13 = 0.69835 / T_star_12^0.22820 ...
             + 0.18120 / exp(0.31842 * T_star_12) ...
             + 1.5095 / exp(1.8902 * T_star_12);

    A_12_star = Omega_22 / Omega_11;
    B_12_star = (5.0*Omega_12_cs - 4.0*Omega_13) / Omega_11;

    %% ===== 分子质量 =====
    m_He = M_He / N_A;   % kg, 单个He分子质量
    m_Xe = M_Xe / N_A;   % kg, 单个Xe分子质量
    m_12 = m_He * m_Xe / (m_He + m_Xe);  % 约化质量

    %% ===== 相互作用粘度 mu_12^0 (Chapman-Enskog 公式) =====
    miu_12_0 = (5.0/16.0) * sqrt(pi * m_12 * k_B * T) / ...
               (pi * sigma_12^2 * Omega_22);

    %% ===== phi_ij (论文公式 2.21) =====
    phi_12 = (miu_He_ideal / miu_12_0) ...
           * (2.0 * m_He * m_Xe / (m_He + m_Xe)^2) ...
           * (5.0 / (3.0 * A_12_star) + m_Xe / m_He);

    phi_21 = (miu_Xe_ideal / miu_12_0) ...
           * (2.0 * m_He * m_Xe / (m_He + m_Xe)^2) ...
           * (5.0 / (3.0 * A_12_star) + m_He / m_Xe);

    %% ===== 混合气体理想粘度 (论文公式 2.20) =====
    miu_mix_ideal = (x_He * miu_He_ideal) / (x_He + x_Xe * phi_12) + ...
                    (x_Xe * miu_Xe_ideal) / (x_He * phi_21 + x_Xe);

    %% ===== 纯组分理想气体导热系数 (Chapman-Enskog = Eucken 单原子) =====
    lambda_He_ideal = (15.0/4.0) * (R0 / M_He) * miu_He_ideal;
    lambda_Xe_ideal = (15.0/4.0) * (R0 / M_Xe) * miu_Xe_ideal;

    %% ===== 相互作用导热系数 lambda_12 (Chapman-Enskog) =====
    lambda_12 = (15.0/4.0) * (k_B / m_12) * miu_12_0;

    %% ===== L_ij 系数 (论文公式 2.25-2.26) =====
    L_11 = x_He^2 / lambda_He_ideal ...
         + (x_He * x_Xe / (2.0 * lambda_12)) ...
           * (7.5*m_He^2 + 6.25*m_Xe^2 - 3.0*m_Xe^2*B_12_star + 4.0*m_He*m_Xe*A_12_star) ...
           / ((m_He + m_Xe)^2 * A_12_star);

    L_22 = x_Xe^2 / lambda_Xe_ideal ...
         + (x_Xe * x_He / (2.0 * lambda_12)) ...
           * (7.5*m_Xe^2 + 6.25*m_He^2 - 3.0*m_He^2*B_12_star + 4.0*m_Xe*m_He*A_12_star) ...
           / ((m_Xe + m_He)^2 * A_12_star);

    L_12 = -(x_He * x_Xe / (2.0 * lambda_12)) ...
           * (m_He * m_Xe / ((m_He + m_Xe)^2 * A_12_star)) ...
           * (55.0/4.0 - 3.0*B_12_star - 4.0*A_12_star);

    %% ===== 混合气体理想导热系数 (论文公式 2.24) =====
    lambda_mix_ideal = (x_He^2 * L_22 - 2.0*x_He*x_Xe*L_12 + x_Xe^2 * L_11) ...
                     / (L_11 * L_22 - L_12^2);

    %% ===== 非理想粘度修正 (论文公式 2.18-2.19) =====
    rho_r = rho / rho_c_Xe;
    Psi_miu = 0.221*rho_r + 1.062*rho_r^2 - 0.509*rho_r^3 + 0.225*rho_r^4;
    miu_Xe_star = sqrt(M_Xe * R0 * T_c_Xe) / (v_Xe^(2.0/3.0) * N_A^(1.0/3.0));
    miu = miu_mix_ideal + (1.0 - 1.0/2.3) * x_Xe * miu_Xe_star * Psi_miu;

    %% ===== 非理想导热系数修正 (论文公式 2.22-2.23) =====
    Psi_lambda = 0.645*rho_r + 0.331*rho_r^2 - 0.0368*rho_r^3 - 0.0128*rho_r^4;
    cv_Xe = 1.5 * R0 / M_Xe;
    lambda_cr_star = 2.5 * miu_Xe_star * cv_Xe;
    lambda = lambda_mix_ideal + (1.0 - 1.0/2.94) * lambda_cr_star * Psi_lambda;

    %% ===== 普朗特数 (论文公式 2.27) =====
    Pr = cp_mass * miu / lambda;

end

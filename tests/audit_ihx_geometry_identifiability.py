"""Conditional geometry/domain audit, NOT a design or replacement h model.

Uses the unchanged, hash-bound scalar property checkpoint. Never runs MATLAB,
loads SLX, integrates an ODE, fits a parameter, or writes outside tmp/.
"""
import csv
import hashlib
import json
import math
from pathlib import Path
import subprocess
import tempfile


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def nu_boundary_checks(cases, point, props, length):
    """Dimensionless/algebraic diagnostics only, NOT an adopted correlation.

    INL/CON-13-30489 PDF4 Eq14 specifies H1 and fully developed laminar
    semicircular flow. INL/CON-15-36180 PDF6 Eq20 defines Nu=h*dh/k;
    PDF9 TableIII distinguishes T/H1/H2. Neither proves Xu's Li boundary.
    The hot input-channel check holds the ACTUAL model area at 7.031 m2:
    this is a drop-in-h diagnostic, not a geometry-consistent redesign.
    """
    cp0 = props['uniform_input_coupling'][1]['cp_uniform_J_kgK']
    ch0 = 4.572*cp0
    area_region = 7.031
    old_ratio = 10544*area_region/(2*ch0)
    rows = []
    for case in cases:
        dh = case['hydraulic_diameter_m']
        diameter = case['semicircle_diameter_m']
        pe = case['Pe_Li']
        velocity = 4.572/(point['rho_h']*case['flow_area_per_side_m2'])
        alpha = point['k_h_W_mK']/(point['rho_h']*point['cp_h_J_kgK'])
        pe_length = velocity*length/alpha
        assert math.isclose(pe_length, pe*length/dh, rel_tol=1e-13)
        nu_d = 4.089*diameter/dh
        h_candidate = case['h_Li_if_NuDh_4p089_W_m2K']
        assert math.isclose(nu_d*point['k_h_W_mK']/diameter,
                            h_candidate, rel_tol=1e-13)
        ratio = h_candidate*area_region/(2*ch0)
        dc_gain = (1-ratio)/(1+ratio)
        # For one region, frozen cp0, prescribed wall and fixed h:
        # x'=2C/B*(Ti-x)-H/B*(x-w)
        # y'=2C/B*(x-y)-H/B*(x-w).
        # A positive inlet step starts x'>0, then y'' has sign(2C-H).
        # This is not a closed-loop stability or full-trajectory result.
        assert ratio > old_ratio > 1 and dc_gain < 0
        rows.append(dict(
            total_wetted_area_over_table_A=case['total_wetted_area_over_table_A'],
            velocity_m_s=velocity, thermal_diffusivity_m2_s=alpha,
            Pe_dh=pe, Pe_L=pe_length, inverse_Pe_L=1/pe_length,
            Graetz_Pe_dh_over_L=pe*dh/length,
            hydrodynamic_length_coordinate_L_over_Re_dh=length/(case['Re_Li']*dh),
            hydraulic_diameter_Nu=4.089, equivalent_physical_diameter_Nu=nu_d,
            h_if_H1_W_m2K=h_candidate, h_over_existing=h_candidate/10544,
            drop_in_only_h_H_over_2C_at_1200K=ratio,
            drop_in_fixed_wall_hot_DC_gain=dc_gain,
        ))
    assert math.isclose(rows[0]['Pe_L'], rows[1]['Pe_L'], rel_tol=1e-13)
    return dict(
        source_urls=[
            'https://inldigitallibrary.inl.gov/content/uploads/50/2026/04/5817344.pdf',
            'https://inldigitallibrary.inl.gov/content/uploads/50/2026/04/Sort_8871.pdf'],
        source_access='Web PDF text inspected; local downloads returned HTTP403; no local PDF visual verification.',
        boundary='H1: axially uniform wall heat flux, circumferentially uniform wall temperature; hydrodynamically and thermally fully developed.',
        interpretation='H1 here is a thermal boundary label, NOT the project H1a/H1b experiments.',
        existing_H_over_2C_at_1200K=old_ratio,
        frozen_cp_for_drop_in_J_kgK=cp0,
        cases=rows,
        limitations=[
            'Geometry and split remain conditional; property checkpoint was not rerun or independently validated.',
            'Pe_L is a characteristic-scale ratio, NOT a bound on axial-conduction or heat-transfer error.',
            'No empirical entrance-length formula or acceptance threshold is imposed.',
            'H1 asymptote is not rejected solely because Li Pr/Pe are low; present inlet/wall conditions remain unverified.',
            'Positive-step/DC check fixes wall, area and cp; it is not a full coupled IHX simulation.',
            'Reject direct h-only promotion, NOT the general H1 laminar solution.',
        ])


def main():
    repo = Path(__file__).resolve().parents[1]
    source = repo/'tmp/steady53_curves_20260828/source_f8bcd83'
    audit = repo/'tmp/tpf0a72ead_e5f7_48b0_bc8f_e26c293b272a/audit.json'
    proof = audit.parent/'independent_verification.json'
    previous = json.loads(proof.read_text())
    assert digest(audit) == previous['input_sha256'][str(audit)]
    protected_manifest = repo/'tmp/tp80484fa0_602f_4386_89ed_ae9ca96b3359/protected_after.csv'
    with protected_manifest.open(newline='') as handle:
        protected = list(csv.DictReader(handle))
    assert len(protected) == 34
    for item in protected:
        assert digest(Path(item['paths'])) == item['hashes'], item['paths']
    props = json.loads(audit.read_text())
    for name, expected in zip(('Lithium_property_simulink.m', 'HeXe_property_simulink.m'),
                              props['source_property_hashes']):
        assert digest(source/name) == expected
    point = props['source_checks'][1]
    assert point['P_c_Pa'] == 1543000
    A, V, L, W, H, plates = 14.062, .00651, .0585, .6, 1.1572, 525
    # Assumptions: straight identical semicircular channels, V is total fluid
    # volume, equal volume by side, H includes only plates, no header/endplate.
    # Case 1: tabulated A = BOTH banks' wetted area combined.
    # Case 2: tabulated A = ONE bank's wetted area (equal banks).
    # These are alternative area conventions, not two approved constructions.
    cases = []
    for factor in (1, 2):
        wet_total = factor*A
        dh = 4*V/wet_total
        diameter = dh*(math.pi+2)/math.pi
        cross = math.pi*diameter**2/8
        perimeter = diameter*(math.pi/2+1)
        count = V/(cross*L)
        tp = H/plates
        delta = tp-math.pi*diameter/8
        side_area = V/(2*L)
        assert math.isclose(4*cross/perimeter, dh, rel_tol=1e-14)
        assert math.isclose(count*perimeter*L, wet_total, rel_tol=1e-14)
        assert math.isclose(count*cross*L, V, rel_tol=1e-14)
        assert diameter/2 < tp and delta > 0
        # Effective channel counts are not rounded to manufacture-ready integers.
        pitch_estimate = W/(count/plates)
        assert pitch_estimate > diameter
        re_li = 4.572*dh/(side_area*point['mu_h_Pa_s'])
        re_xe = 11.97*dh/(side_area*point['mu_c_Pa_s'])
        pe_li = re_li*point['Pr_h']
        # Independent Pe expression: viscosity cancels in Re*Pr.
        independent_pe = 4.572*point['cp_h_J_kgK']*dh/(side_area*point['k_h_W_mK'])
        assert math.isclose(pe_li, independent_pe, rel_tol=1e-13)
        checks = {
            'Lyon_Pe_300_to_10000': 300 < pe_li < 10000,
            'Lubarsky_Kaufman_Pe_200_to_10000': 200 < pe_li < 10000,
            'Reed_Pe_above_100': pe_li > 100,
            'Dittus_Boelter_Prc_0p7_to_120': .7 < point['Pr_c'] < 120,
            'Gnielinski_Prc_0p5_to_2000': .5 < point['Pr_c'] < 2000,
        }
        assert not any(checks.values())
        cases.append(dict(
            total_wetted_area_over_table_A=factor, hydraulic_diameter_m=dh,
            semicircle_diameter_m=diameter, conditional_plate_thickness_m=tp,
            conditional_effective_wall_thickness_m=delta,
            effective_channel_count=count, effective_channels_per_plate=count/plates,
            estimated_pitch_without_edge_margin_m=pitch_estimate,
            flow_area_per_side_m2=side_area, Re_Li=re_li, Re_HeXe=re_xe,
            Pe_Li=pe_li, L_over_dh=L/dh, correlation_domain_gates=checks,
            h_Li_if_NuDh_4p089_W_m2K=4.089*point['k_h_W_mK']/dh,
            Nu4p089_status='Conditional use of Nu based on dh; liquid-Li and entrance/boundary applicability UNVERIFIED; not applied.',
        ))
    assert math.isclose(cases[0]['hydraulic_diameter_m'],
                        2*cases[1]['hydraulic_diameter_m'], rel_tol=1e-14)
    report = dict(
        scope='Geometry identifiability and correlation-domain checks only; no new h, trajectory or approval.',
        paper_inputs=dict(A_m2=A, V_channel_m3=V, L_m=L, W_m=W, H_m=H, plates=plates, mass_kg=325),
        assumptions=[
            'Same semicircular geometry for all channels; full wetted perimeter includes flat diameter.',
            'Table volume is total for both sides; equal division is a hypothesis, not an original input.',
            'H/plates excludes end plates and headers; effective counts do not identify integer layout.',
            'Area interpretations are algebraic alternatives, not recovered author designs.',
        ],
        property_checkpoint=dict(path=str(audit), sha256=digest(audit), values=point,
                                 status='Previously executed scalar checkpoint, verified unchanged; not rerun.'),
        cases=cases,
        nu_boundary=nu_boundary_checks(cases, point, props, L),
        domain_source=dict(url='https://inldigitallibrary.inl.gov/sites/sti/sti/5901289.pdf',
                           report='INL/EXT-13-30047', location='PDF27, printed12, Table2',
                           limit='Bounds checked as reported here; original cited correlation papers not rederived.'),
        cited_142=dict(path=str(repo.parent/(repo.name+'_副本')/'1437159.pdf'),
                      location='PDF30-31, printed3-4, Table1',
                      finding='Straight semicircular laminar Nu=4.089 is present; local Li applicability not established.'),
        source_sha256={str(p):digest(p) for p in [Path(__file__), audit, proof,
            repo/'空间锂冷堆He-Xe布雷顿循环发电系统优化设计与运行特性分析_徐驰.pdf',
            repo/'tmp/steady53_curves_20260828/equations-098.png',
            repo/'tmp/ihx_equation_source_n1I14d/thesis-047.png',
            repo.parent/(repo.name+'_副本')/'1437159.pdf']},
        protected_files_unchanged=len(protected),
    )
    run = Path(tempfile.mkdtemp(prefix='ihx_geometry_audit_', dir=repo/'tmp'))
    (run/'audit.json').write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    for item in protected:
        assert digest(Path(item['paths'])) == item['hashes'], item['paths']
    archive = subprocess.check_output(['git','-C',str(repo),'rev-parse',
                                       'archive/pre-restart-20260824^{}'],text=True).strip()
    assert archive == '8f625c268c35a95c18a626305c1aa6a79ae2ace7'
    print(json.dumps(cases, indent=2))
    print('IHX_GEOMETRY_IDENTITIES_AND_DOMAIN_GATES_PASS; PROTECTED_UNCHANGED=34')
    print(json.dumps(report['nu_boundary'], indent=2))
    print('NU_BOUNDARY_SCALE_AND_DROP_IN_SIGN_CHECKS_PASS_NO_SIMULATION')
    print('OUTPUT_DIRECTORY='+str(run))


if __name__ == '__main__':
    main()

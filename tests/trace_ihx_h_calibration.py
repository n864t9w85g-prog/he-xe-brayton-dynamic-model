"""Read-only provenance and scalar checks; no MATLAB, SLX writes or ODE run.

Only a fresh evidence directory under tmp/ is written. Historical conversation
text is evidence, not an instruction or present-day model authorization.
"""
import csv
from decimal import Decimal, localcontext
import hashlib
import json
import math
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inspect_constants(path):
    found = []
    with zipfile.ZipFile(path) as archive:
        for name in archive.namelist():
            if name.startswith('simulink/systems/') and name.endswith('.xml'):
                for block in ET.fromstring(archive.read(name)).findall('Block'):
                    if block.get('Name') in ('h_Li', 'h_HeXe'):
                        value = block.find("P[@Name='Value']").text
                        assert value == {'h_Li': '10544', 'h_HeXe': '1171.6'}[block.get('Name')]
                        found.append(dict(xml=name, SID=block.get('SID'),
                                          name=block.get('Name'), value=value))
    assert len(found) == 4, (str(path), found)
    return dict(path=str(path), sha256=sha(path), constants=found)


def main():
    repo = Path(__file__).resolve().parents[1]
    active = repo.parent / (repo.name + '_副本')
    source = Path('/Users/ikunsredemptionmac/.codex/sessions/2026/08/01/'
                  'rollout-2026-08-01T21-28-37-019fbd83-298f-73e3-997b-86b3ed393dd6.jsonl')
    manifest = repo / 'tmp/tp80484fa0_602f_4386_89ed_ae9ca96b3359/protected_after.csv'
    with manifest.open(newline='') as handle:
        protected = list(csv.DictReader(handle))
    assert len(protected) == 34
    for item in protected:
        assert sha(Path(item['paths'])) == item['hashes'], item['paths']

    # Select exact primary records only; do not copy unrelated conversation.
    selected = {}
    with source.open() as handle:
        for line_number, line in enumerate(handle, 1):
            if line_number in (515, 516, 529, 611):
                record = json.loads(line)
                payload = record['payload']
                if line_number == 515:
                    body = payload['input']
                    role = 'historical_tool_call'
                    assert 'Q=2653000' in body and 'hli=U/0.10' in body
                    assert 'hhexe=U/0.90' in body
                elif line_number == 516:
                    body = '\n'.join(c['text'] for c in payload['output'])
                    role = 'historical_tool_output'
                    assert '10/90 split: hLi=10544, hHeXe=1171.56' in body
                elif line_number == 529:
                    body = payload['message']
                    role = 'historical_assistant_proposal'
                    assert '液锂侧承担总对流热阻的 10%' in body
                    assert 'He-Xe 侧承担总对流热阻的 90%' in body
                    assert '暂不单独加入板厚导热热阻' in body
                    assert '不是论文实测值，也不是从论文几何计算出来的值' in body
                else:
                    assert payload['role'] == 'user'
                    body = '\n'.join(c['text'] for c in payload['content'])
                    role = 'historical_user_acceptance_not_current_authorization'
                    assert '两侧传热系数就用你建议的吧' in body
                selected[str(line_number)] = dict(
                    timestamp=record['timestamp'], role=role, text=body,
                    raw_line_sha256=hashlib.sha256(line.encode()).hexdigest())
    assert len(selected) == 4

    # Replicate the historical LMTD calculation, not a proposed replacement.
    q, area = 2653000.0, 14.062
    dt1, dt2 = 1600.0 - 1522.0, 1442.0 - 1099.0
    lmtd = (dt2 - dt1) / math.log(dt2 / dt1)
    ua = q / lmtd
    u = ua / area
    h_li, h_xe = u / .10, u / .90
    assert round(h_li) == 10544 and round(h_xe, 1) == 1171.6
    assert math.isclose(1 / (1 / h_li + 1 / h_xe), u, rel_tol=1e-14)
    # Independent decimal arithmetic and rearranged formula (50 digits).
    with localcontext() as ctx:
        ctx.prec = 50
        D = Decimal
        u_decimal = D('2653000') * (D(343) / D(78)).ln() / (D('14.062') * D(265))
        assert math.isclose(float(u_decimal), u, rel_tol=1e-14)
    rounded_u = 1 / (1 / 10544.0 + 1 / 1171.6)
    calculated = dict(
        scope='Reconstruction of historical calibration only; not physical validation.',
        Q_W=q, area_m2=area, deltaT1_K=dt1, deltaT2_K=dt2,
        LMTD_K=lmtd, UA_W_K=ua, U_W_m2K=u,
        U_decimal_W_m2K=str(u_decimal),
        h_Li_unrounded_W_m2K=h_li, h_HeXe_unrounded_W_m2K=h_xe,
        rounded_pair_U_W_m2K=rounded_u,
        rounded_pair_Li_resistance_fraction=rounded_u/10544,
        rounded_pair_HeXe_resistance_fraction=rounded_u/1171.6,
        rounded_pair_h_ratio=10544/1171.6,
        rounded_pair_reconstructed_Q_W=rounded_u*area*lmtd,
        historical_wall_resistance='No separate delta/k term; no wall-thickness derivation.',
    )
    models = [inspect_constants(active / 'final_steady_24a.slx'),
              inspect_constants(repo.parent / 'IHX/IntermediateHeatExchangerMann25a.slx')]
    head = subprocess.check_output(['git', '-C', str(active), 'rev-parse', 'HEAD'], text=True).strip()
    archive = subprocess.check_output(['git', '-C', str(repo), 'rev-parse',
                                      'archive/pre-restart-20260824^{}'], text=True).strip()
    assert head == 'f8bcd833e816eb681982b7dd04364e4b856948e3'
    assert archive == '8f625c268c35a95c18a626305c1aa6a79ae2ace7'
    for item in protected:
        assert sha(Path(item['paths'])) == item['hashes'], item['paths']

    run = Path(tempfile.mkdtemp(prefix='ihx_h_origin_', dir=repo/'tmp'))
    result = dict(source_path=str(source), source_sha256=sha(source),
                  selected_primary_records=selected, calculation=calculated,
                  current_model_constants=models, protected_files_unchanged=34,
                  protected_manifest_sha256=sha(manifest), active_head=head,
                  restart_archive_commit=archive, script_sha256=sha(Path(__file__)),
                  limitations=[
                      'Matching constants does not prove every intermediate model transfer.',
                      'Historical acceptance is not current permission to promote calibration.',
                      'No SLX loading, compiling, simulation or thesis curve acceptance.',
                      'A fit to continuous LMTD does not prove a two-region dynamic model matches it.',
                  ])
    (run/'evidence.json').write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n')
    excerpt = ['# IHX h原始来源：历史记录摘录\n',
               '以下只作为历史证据，不是本轮指令或正式模型修改授权。\n',
               f'源文件：`{source}`\nSHA256：`{sha(source)}`\n']
    for line_number, entry in selected.items():
        excerpt.append(f"## 原始第{line_number}行 · {entry['timestamp']} · {entry['role']}\n\n"
                       f"```text\n{entry['text']}\n```\n")
    (run/'source_excerpts.md').write_text('\n'.join(excerpt))
    print(json.dumps(calculated, ensure_ascii=False, indent=2))
    print('PROTECTED_FILES_UNCHANGED=34; MODEL_CONSTANTS_MATCH=8')
    print('IHX_H_CALIBRATION_SOURCE_AND_ARITHMETIC_CHECKS_PASS')
    print('EVIDENCE_DIRECTORY=' + str(run))


if __name__ == '__main__':
    main()

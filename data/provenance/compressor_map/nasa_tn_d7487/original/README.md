# NASA TN D-7487 压气机程序：FORTRAN 转录与 Python 版

本目录整理了 Michael R. Galvas 在 NASA TN D-7487 *FORTRAN Program for
Predicting Off-Design Performance of Centrifugal Compressors* 中刊出的离心压气机
非设计点程序，并将其结构化转写为可直接运行的 Python 程序。

## 交付文件

- `compressor_program.py`：完整 Python 程序，只使用标准库。
- `sample_input.json`：报告图 5 的 100% 设计转速示例输入。
- `fortran_transcription.f`：主程序及 `LININT` 的固定格式转录，并附重建的
  `FNTGRL`。
- `test_compressor_program.py`：单元测试、出版样例数值对照和 CLI 测试。
- `README.md`：本说明。

## Source Provenance

原始文件为 `压气机程序 (Compressor Program).pdf`，报告编号 NASA TN D-7487，
1973 年 11 月出版。相关位置如下：

- 图 5（report page 11）：示例 NAMELIST 输入。
- 主程序清单（report pages 26-33）：压气机入口、叶轮、无叶扩压器、有叶扩压器、
  两遍运行控制和输出格式。
- `LININT`（report page 34）：完整 FORTRAN 子程序清单。
- `FNTGRL`（report page 35）：只有接口和三条积分公式。

报告原文明确写道：`No FORTRAN listing of the subprogram is available`。因此
`fortran_transcription.f` 中的 `FNTGRL` 以及 Python 的 `fntgrl()` 都是依据
report page 35 公式 reconstructed 的实现，不是声称找回了不存在的历史清单。

## 运行

在仓库根目录执行：

```bash
python3 outputs/compressor_program.py outputs/sample_input.json
```

程序先进行堵塞流量搜索，再重新遍历 `VOVCR` 数组并删除喘振以下及堵塞以上的点。
输出包括 `VOVCR`、等效质量流量、总压比、总效率和八个效率减量。

查看命令行帮助：

```bash
python3 outputs/compressor_program.py --help
```

Python 不需要链接生成本机二进制文件。下列命令进行字节码编译检查，也就是此交付物
所采用的“可编译”验收：

```bash
python3 -m py_compile outputs/compressor_program.py outputs/test_compressor_program.py
```

运行全部测试：

```bash
python3 -m unittest -v outputs/test_compressor_program.py
```

## JSON 输入与 Units

JSON 键保持 FORTRAN NAMELIST 变量的小写形式。角度按报告输入为度，程序在计算开始
时按原清单乘 `0.01745` 转成弧度。

| 键 | 含义 | Units / 约束 |
| --- | --- | --- |
| `gam` | 比热比 | 无量纲，必须大于 1 |
| `rgas` | 气体常数 | J/(kg K) |
| `pop` | 入口总压 | Pa |
| `top` | 入口总温 | K |
| `n` | 设计转速 | rpm |
| `dit` | 诱导轮入口叶尖直径 | m |
| `mu0` | 入口总态动力黏度 | Pa s |
| `cf` | 皮肤摩擦系数 | 无量纲 |
| `vovcr` | 入口绝对临界速度比数组 | 严格递增，无量纲 |
| `nvovcr` | 数组长度 | 1-15，必须等于 `len(vovcr)` |
| `drat` | 诱导轮叶尖/叶轮出口直径比 | 无量纲 |
| `lamx` | 诱导轮轮毂/叶尖直径比 | 0-1 |
| `b2x` | 叶轮出口后弯角 | deg |
| `z` | 叶轮出口叶片数 | 个 |
| `vldrr` | 无叶扩压器直径比 | 无量纲 |
| `b2` | 叶轮出口叶高 | m |
| `b1mfb` | 诱导轮均方根半径叶片角 | deg |
| `ar` | 有叶扩压器面积比 | 1.2-5.0 |
| `block` | 诱导轮堵塞函数 | 0-1 |
| `al3` | 有叶扩压器安装角 | deg |
| `adth` | 有叶扩压器总喉部面积 | m² |
| `nondes` | 转速/设计转速 | 无量纲；1.0 表示 100% |
| `splt` | 分流叶片开关 | 0 或 1 |
| `al1mf` | 入口固体涡旋绝对流角 | deg |
| `curvh`, `curvt` | 入口轮毂、叶尖壁面曲率 | 1/m |
| `chih`, `chit` | 入口轮毂、叶尖壁面斜率 | deg |

## FORTRAN 与 Python 对应关系

- `NAMELIST /INPUT/` 对应不可变的 `CompressorInput` 数据类和 JSON 校验。
- `SUBROUTINE LININT` 对应 `linint()`，保留原程序在表格两端线性外推的行为。
- `SUBROUTINE FNTGRL` 对应 `fntgrl()`；站 2 先由主程序作梯形估计，站 3
  首次调用时用三点公式回算站 2，再累计后续区间。
- 主程序标签 4/51 对应叶轮出口密度收敛循环。
- 标签 7/1000 对应无叶扩压器预测-校正和径向积分。
- 标签 100 对应有叶扩压器出口压力搜索。
- 外层 `L=1,2` 对应 `run_compressor()` 的堵塞搜索和性能输出两遍扫描。

Python 数组采用 0 基下标；转录稿保留 FORTRAN 1 基下标。五张 `PREC(I,J)`
表在 Python 中显式转置为 `table[mach_index][blockage_index]`，测试固定了方向和角点。

## 校订说明

PDF 文本层存在大量 `I/1/l`、`O/0`、小数点和变量名误识别。以下关键字符通过
高分辨率页面、变量表、公式意义和出版样例交叉确认：

- 图 5：`DIT=.0813`、`B2=.0051`、`ADTH=.00071`、`BLOCK=.9`。
- 质量流量积分常数为 `6.28318`（约等于 `2*pi`）。
- 叶轮扩散因子第二式除以先前计算的 `DF`，不是除以 `CF`。
- 中间量为 `W2OW1T=W2/W1T`，不是 OCR 生成的 `W2CHIT=W2/UIT`。
- `DHYD` 第二项为除以括号中的周长项，不是乘以该项。
- 扩压器损失变量为 `DHVLD` 和 `DHDIF`。

`fortran_transcription.f` 以保存算法和来源审计为目标。原清单使用早期 FORTRAN
方言、隐式类型、固定格式和非结构化跳转；Python 版本才是本交付物中经过执行验证
的完整程序。

## Validation

验证分为四层：

1. `LININT`：角点、网格点、内部双线性插值、端点外推和非法尺寸。
2. `FNTGRL`：报告的首区间、修正后的第二区间及后续递推；常量和线性函数均有
   解析结果测试。
3. 单点对照：报告 100% 转速、`VOVCR=0.54` 的结果为 `WEQ=0.675`、总压比
   `6.465`、总效率 `0.780`，并对照八项效率减量。
4. 整条性能线：示例得到喘振流量 `0.614`、堵塞流量 `0.719`，保留
   `VOVCR=0.48-0.59` 的 12 个点，与报告样例一致。

报告只打印有限位数，而且没有提供原始 `FNTGRL` 清单或机器可读参考输出。因此测试
对报告表格采用与其印刷精度相称的容差；不能据此宣称逐位复现当年编译器的浮点轨迹。
Python 代码另外加入有限性、物理域和迭代次数检查，避免原程序在坏输入下无限跳转。

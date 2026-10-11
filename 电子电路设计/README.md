# 电子电路设计：DDS 波形发生器

面向 DMZ-EG4S20 FPGA 开发板的直接数字频率合成（DDS）波形发生器。工程通过板载 R-2R DAC 输出波形，并提供 PWM、4×4 矩阵键盘、数码管、UART 和蜂鸣器旋律播放功能。

## 功能

- 输出正弦、方波、三角波与锯齿波。
- 频率范围为 100 Hz–10 kHz，步进 100 Hz。
- 8 位幅度控制，输出到 DAC 与 PWM。
- 矩阵键盘控制波形、频率、幅度及复位。
- UART（115200-8N1）接收参数帧，在线设置波形、频率与幅度。
- `Song_Enable` 控制蜂鸣器播放《兰花草》旋律；播放期间覆盖 DDS 参数，停止后恢复原设置。
- 四位数码管显示频率、波形和幅度状态。

## 项目结构

```text
电子电路设计/
└── dds_gen/
    ├── dds_wavegen_top.v        # 顶层 RTL 与功能模块
    ├── dds_wavegen.adc          # 引脚与 IO 约束
    ├── dds_wavegen.sdc          # 50 MHz 时钟约束
    ├── dds-gen.al               # TD 工程文件
    ├── build_td_flat_project.tcl # 命令行构建脚本
    ├── al_ip/                   # DDS IP 配置及门级模型
    ├── tb_*.v                   # Verilog 测试平台
    ├── dds_wavegen_top_sim/     # ModelSim 仿真脚本与波形配置
    └── uart_send_params.py       # UART 参数发送工具
```

## 硬件与工具

- 开发板：DMZ-EG4S20（器件 `EG4S20BG256`）
- 系统时钟：50 MHz
- FPGA 工具：TD（工程文件记录版本 5.6.151449）
- 仿真：ModelSim/Questa，使用 `dds_wavegen_top_sim/behav_sim` 下的 `.do` 脚本
- 串口工具：Python 3；实际发送时需要 `pyserial`

## 构建

在 TD 工具环境中执行：

```tcl
cd dds_gen
source build_td_flat_project.tcl
```

脚本读取顶层 RTL、DDS IP、ADC 与 SDC 约束，并在 `build_td_fix/` 生成位流。该目录中的生成文件不提交到 Git。

## 键盘控制

| 按键 | 功能 |
| --- | --- |
| KEY0 | 切换波形：正弦 → 方波 → 三角波 → 锯齿波 |
| KEY1 / KEY2 | 频率 +100 Hz / −100 Hz |
| KEY3 | 复位为正弦波、1 kHz、满幅度 |
| KEY4 / KEY5 | 幅度 +16 / −16 |

## UART 协议

帧格式为 `A5 wave freq amplitude checksum`，校验和为前四个字节的 XOR。

- `wave`：`0=sine`、`1=square`、`2=triangle`、`3=saw`
- `freq`：频率除以 100，范围 1–100
- `amplitude`：0–255

例如，仅查看将发送给 `COM3` 的 1 kHz 正弦满幅帧：

```powershell
python .\dds_gen\uart_send_params.py COM3 sine 1000 255 --dry-run
```

去掉 `--dry-run` 后将向指定串口发送数据。

## 验证

- `tb_dds_wavegen_top.v`：顶层功能、按键、DAC、PWM 与数码管检查。
- `tb_all_waveforms_one_cycle.v`、`tb_sine_one_cycle.v`、`tb_square_one_cycle.v`：波形周期检查。
- `tb_uart_pwm.v`：UART 设置和 PWM 检查。
- `tb_song_mode.v`：蜂鸣器旋律模式检查。

## 版本控制说明

提交 RTL、约束、IP 配置、构建脚本、测试平台和仿真脚本；忽略位流、综合/布局布线报告、仿真工作目录、串口终端程序与本地日志。

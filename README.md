整合了
[fumiama/go-nd-portal](https://github.com/fumiama/go-nd-portal)
以及
[Aleksanaa/qsh-telecom-autologin](https://github.com/Aleksanaa/qsh-telecom-autologin)
进行自动化登录认证的LuCI App。
## 界面预览
![image](https://github.com/user-attachments/assets/99c90228-4822-4d16-ac8f-0fa4334ac92a)
## 功能特性
* **在网络掉线后，自动重新进行认证**
* **定时断开网络连接，避免在高峰使用时间段的认证掉线**
* **支持多种认证方式：**
    * 清水河教学办公区、新宿舍区的统一认证方式
    * 清水河老宿舍区电信认证方式
    * 后续将支持沙河
* **同时管理多个接口上的认证配置**
## 使用方法
### 方法1：直接从Release下载
根据架构，现在提供了在 `OpenWrt 21.02.7` 以及 `OpenWrt 24.10.1` SDK下编译好的ipk文件。
* `mediatek/mt7622` 以及 `qualcommax/ipq807x` 对应`aarch64-cortex-a53` 架构。
### 方法2：使用GitHub Actions
`fork` 该仓库，修改main分支 `ci.yml` 中的 `build_ipks_for_target`。在Actions中手动触发编译即可。
* 在 `matrix`中添加需要的 `openwrt_version`, `openwrt_target_arch`, 以及 `openwrt_target_subtarget`。
### 方法3：自行编译
下载OpenWrt SDK源码，将该仓库添加为 `feed`。
```
echo "src-git https://github.com/chasey-dev/uestc_authclient;main" >> feeds.conf
```
然后在make menuconfig中勾选编译即可。
## 注意事项
已在OpenWrt 21.02.7与OpenWrt 24.10.1上的 `aarch64-cortex-a53` 进行测试，其余设备及版本不做任何兼容性保证。
* App基于LuCI2架构，注意安装相关运行环境。
* 推荐在启用DSA模式的固件上使用，swconfig模式下未进行详细测试。
* 在 `ramips`架构上的编译会出现问题。

import os
import re
import subprocess
from typing import Dict, List, Tuple


CONF_FILE_PEZHI = os.environ.get("NGINX_MANAGER_CONF_PATH", "/etc/nginx/conf.d/forward3000.conf")
CONF_DIR_PEZHI = os.environ.get("NGINX_MANAGER_CONF_DIR", os.path.dirname(CONF_FILE_PEZHI) or os.getcwd())
RULE_PREFIX_PEZHI = os.environ.get("NGINX_MANAGER_RULE_PREFIX", "forward")
DEFAULT_PORT_PEZHI = os.environ.get("NGINX_MANAGER_DEFAULT_PORT", "3000")
NGINX_BIN_PEZHI = os.environ.get("NGINX_MANAGER_NGINX_BIN", "nginx.exe" if os.name == "nt" else "/usr/sbin/nginx")


# 函数说明:
# 参数：
# 返回：格式化后的域名展示文本
def format_yuming_shuchu(yuming_zifu: str) -> str:
    yuming_guilv = yuming_zifu.strip()
    if yuming_guilv in ("", "_", "*"):
        return "所有域名"
    return yuming_guilv


# 函数说明:
# 参数：规则文件路径
# 返回：监听端口、匹配域名
def parse_wenjian_xinxi(path_wenjian: str) -> Tuple[str, str]:
    port_jianting = "unknown"
    yuming_pipei = "_"
    try:
        with open(path_wenjian, "r", encoding="utf-8") as file_duru:
            neirong_quanbu = file_duru.read()
    except OSError:
        return port_jianting, yuming_pipei

    listen_pipei = re.search(r"listen\s+(\d+)\s*;", neirong_quanbu)
    if listen_pipei:
        port_jianting = listen_pipei.group(1).strip()

    server_name_pipei = re.search(r"server_name\s+([^;]+)\s*;", neirong_quanbu)
    if server_name_pipei:
        yuming_pipei = server_name_pipei.group(1).strip()

    return port_jianting, yuming_pipei


# 函数说明:
# 参数：规则文件路径
# 返回：规则数据结构字典，键为 path
def load_lujing_guize(path_wenjian: str) -> Dict[str, dict]:
    rules_guize: Dict[str, dict] = {}
    try:
        with open(path_wenjian, "r", encoding="utf-8") as file_juzhen:
            data_neirong = file_juzhen.read()
    except FileNotFoundError:
        return rules_guize
    except OSError as error_xinxi:
        print(f"读取配置失败: {error_xinxi}")
        return rules_guize

    blocks_kuaizu = re.findall(r"location\s+/(.*?)\s*{(.*?)}", data_neirong, re.S)
    for path_yuanshi, body_neirong in blocks_kuaizu:
        path_guilv = path_yuanshi.strip().lstrip("/")
        if path_guilv == "":
            continue

        target_pipei = re.search(r"proxy_pass\s+http://([^\s;]+);", body_neirong)
        target_dizhi = target_pipei.group(1).strip() if target_pipei else ""

        websocket_pipei = bool(
            re.search(
                r"proxy_http_version\s+1\.1;|proxy_set_header\s+Upgrade\s+\$http_upgrade;|proxy_set_header\s+Connection\s+\"?upgrade\"?",
                body_neirong,
            )
        )

        headers_zidian: Dict[str, str] = {}
        for key_mingcheng, val_yuanzhi in re.findall(r"proxy_set_header\s+([^\s]+)\s+(.+?);", body_neirong):
            key_guilv = key_mingcheng.strip()
            val_guilv = val_yuanzhi.strip()
            if val_guilv.startswith('"') and val_guilv.endswith('"'):
                val_guilv = val_guilv[1:-1]
            if websocket_pipei and key_guilv.lower() in ("upgrade", "connection"):
                val_lower = val_guilv.lower()
                if val_lower in ("$http_upgrade", "upgrade"):
                    continue
            headers_zidian[key_guilv] = val_guilv

        rules_guize[path_guilv] = {
            "path": path_guilv,
            "target": target_dizhi,
            "websocket": websocket_pipei,
            "headers": headers_zidian,
        }
    return rules_guize


# 函数说明:
# 参数：规则文件路径、端口、域名、规则字典
# 返回：布尔值，True 表示保存成功
def save_lujing_guize(path_wenjian: str, port_jianting: str, yuming_pipei: str, rules_guize: Dict[str, dict]) -> bool:
    conf_hanglie: List[str] = [
        "server {",
        f"    listen {port_jianting};",
        f"    server_name {yuming_pipei};",
    ]

    for path_jian in sorted(rules_guize.keys()):
        rule_dange = rules_guize[path_jian]
        path_guilv = str(rule_dange["path"]).lstrip("/")
        if path_guilv == "":
            continue

        conf_hanglie.append(f"    location /{path_guilv} {{")
        conf_hanglie.append(f"        proxy_pass http://{rule_dange['target']};")
        if rule_dange.get("websocket"):
            conf_hanglie.append("        proxy_http_version 1.1;")
            conf_hanglie.append("        proxy_set_header Upgrade $http_upgrade;")
            conf_hanglie.append('        proxy_set_header Connection "upgrade";')

        for header_jian, header_zhi in rule_dange.get("headers", {}).items():
            value_zhuanyi = str(header_zhi).replace('"', '\\"')
            conf_hanglie.append(f'        proxy_set_header {header_jian} "{value_zhuanyi}";')
        conf_hanglie.append("    }")

    conf_hanglie.append("    location / {")
    conf_hanglie.append("        return 444;")
    conf_hanglie.append("    }")
    conf_hanglie.append("}")

    try:
        with open(path_wenjian, "w", encoding="utf-8", newline="\n") as file_xieru:
            file_xieru.write("\n".join(conf_hanglie))
        return True
    except OSError as error_xinxi:
        print(f"保存配置失败: {error_xinxi}")
        return False


# 函数说明:
# 参数：无
# 返回：规则文件信息列表
def load_guizewenjian_liebiao() -> List[dict]:
    wenjian_liebiao: List[dict] = []
    try:
        os.makedirs(CONF_DIR_PEZHI, exist_ok=True)
        all_wenjian = os.listdir(CONF_DIR_PEZHI)
    except OSError as error_xinxi:
        print(f"读取规则目录失败: {error_xinxi}")
        return wenjian_liebiao

    for wenjian_ming in sorted(all_wenjian):
        if not wenjian_ming.startswith(RULE_PREFIX_PEZHI):
            continue
        if not wenjian_ming.endswith(".conf"):
            continue

        path_wenjian = os.path.join(CONF_DIR_PEZHI, wenjian_ming)
        if not os.path.isfile(path_wenjian):
            continue

        port_jianting, yuming_pipei = parse_wenjian_xinxi(path_wenjian)
        wenjian_liebiao.append(
            {
                "filename": wenjian_ming,
                "filepath": path_wenjian,
                "port": port_jianting,
                "domain": yuming_pipei,
            }
        )

    def sort_key_qiehuan(item_dange: dict) -> Tuple[int, str]:
        port_zifu = str(item_dange.get("port", "unknown"))
        if port_zifu.isdigit():
            return int(port_zifu), str(item_dange.get("filename", ""))
        return 99999, str(item_dange.get("filename", ""))

    wenjian_liebiao.sort(key=sort_key_qiehuan)
    return wenjian_liebiao


# 函数说明:
# 参数：无
# 返回：无
def ensure_moren_guizewenjian() -> None:
    try:
        os.makedirs(CONF_DIR_PEZHI, exist_ok=True)
    except OSError as error_xinxi:
        print(f"创建规则目录失败: {error_xinxi}")
        return

    path_moren = os.path.join(CONF_DIR_PEZHI, f"{RULE_PREFIX_PEZHI}{DEFAULT_PORT_PEZHI}.conf")
    if os.path.exists(path_moren):
        return

    save_ok = save_lujing_guize(path_moren, DEFAULT_PORT_PEZHI, "_", {})
    if save_ok:
        print(f"已创建默认规则文件: {path_moren}")


# 函数说明:
# 参数：无
# 返回：布尔值，True 表示 nginx 可执行文件可用
def check_nginx_zhixing() -> bool:
    try:
        result_pipei = subprocess.run(
            [NGINX_BIN_PEZHI, "-v"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        return result_pipei.returncode in (0, 1)
    except FileNotFoundError:
        return False
    except OSError:
        return False


# 函数说明:
# 参数：规则文件路径
# 返回：布尔值，True 表示 nginx 已包含当前规则文件
def check_conf_yinyong(path_wenjian: str) -> bool:
    dump_jieguo = subprocess.run(
        [NGINX_BIN_PEZHI, "-T"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if dump_jieguo.returncode != 0:
        print("无法通过 nginx -T 确认 include 关系，继续尝试 -t/reload。")
        if dump_jieguo.stderr.strip():
            print(dump_jieguo.stderr.strip())
        return True

    all_neirong = (dump_jieguo.stdout + "\n" + dump_jieguo.stderr).replace("\\", "/")
    conf_guanjian = path_wenjian.replace("\\", "/")
    conf_wenjian = os.path.basename(conf_guanjian)

    if conf_guanjian in all_neirong:
        return True
    if conf_wenjian and conf_wenjian in all_neirong:
        return True

    print(f"警告: nginx 主配置未检测到 include 当前文件: {path_wenjian}")
    print("请检查 nginx.conf 中是否包含 conf.d/*.conf 或该文件的明确 include 语句。")
    return False


# 函数说明:
# 参数：规则文件路径
# 返回：布尔值，True 表示测试并 reload 成功
def apply_nginx_peizhi(path_wenjian: str) -> bool:
    if not check_nginx_zhixing():
        print(f"未找到 nginx 可执行文件: {NGINX_BIN_PEZHI}")
        print("已保存配置文件，但 nginx 未自动生效。")
        return False

    if not check_conf_yinyong(path_wenjian):
        print(f"已保存配置文件，但当前规则文件未被 nginx 引用，故不会生效: {path_wenjian}")
        return False

    test_jieguo = subprocess.run(
        [NGINX_BIN_PEZHI, "-t"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if test_jieguo.returncode != 0:
        print("nginx -t 校验失败，未执行 reload。")
        if test_jieguo.stdout.strip():
            print(test_jieguo.stdout.strip())
        if test_jieguo.stderr.strip():
            print(test_jieguo.stderr.strip())
        return False

    reload_jieguo = subprocess.run(
        [NGINX_BIN_PEZHI, "-s", "reload"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if reload_jieguo.returncode != 0:
        print("nginx reload 失败。")
        if reload_jieguo.stdout.strip():
            print(reload_jieguo.stdout.strip())
        if reload_jieguo.stderr.strip():
            print(reload_jieguo.stderr.strip())
        return False

    print("nginx 配置已生效（已通过 -t 并 reload）。")
    return True


# 函数说明:
# 参数：guize_zidian 规则字典
# 返回：按 path 排序后的列表
def sort_lujingguize_liebiao(rules_guize: Dict[str, dict]) -> List[dict]:
    return [rules_guize[path_jian] for path_jian in sorted(rules_guize.keys())]


# 函数说明:
# 参数：guize_liebiao 规则列表
# 返回：无
def print_lujingguize_liebiao(rules_liebiao: List[dict]) -> None:
    print("\n=== 当前规则列表 ===")
    if not rules_liebiao:
        print("暂无规则。")
        return

    for index_xuhao, rule_dange in enumerate(rules_liebiao, start=1):
        status_qiyong = "开启" if rule_dange.get("websocket") else "关闭"
        print(
            f"{index_xuhao}. path=/{rule_dange['path']} | target={rule_dange['target']} | wss={status_qiyong}"
        )
        headers_zidian = rule_dange.get("headers", {})
        if headers_zidian:
            for header_jian, header_zhi in headers_zidian.items():
                print(f"   - header: {header_jian} = {header_zhi}")


# 函数说明:
# 参数：无
# 返回：用户输入字符串
def input_wenben(prompt_wenan: str) -> str:
    return input(prompt_wenan).strip()


# 函数说明:
# 参数：无
# 返回：端口字符串
def input_duankou() -> str:
    while True:
        duankou_yuanshi = input_wenben("请输入要监听的端口号: ")
        if not duankou_yuanshi.isdigit():
            print("端口必须是数字。")
            continue
        duankou_shuzi = int(duankou_yuanshi)
        if duankou_shuzi < 1 or duankou_shuzi > 65535:
            print("端口范围必须在 1~65535。")
            continue
        return duankou_yuanshi


# 函数说明:
# 参数：无
# 返回：域名字符串，空则返回 _
def input_yuming() -> str:
    yuming_yuanshi = input_wenben("请输入匹配的域名(空为任意域名): ")
    if yuming_yuanshi == "":
        return "_"
    return yuming_yuanshi


# 函数说明:
# 参数：无
# 返回：布尔值，True 为启用 wss
def input_wss_kaiguan() -> bool:
    while True:
        value_yuanshi = input_wenben("是否启用 wss？(y/n): ").lower()
        if value_yuanshi in ("y", "yes", "1"):
            return True
        if value_yuanshi in ("n", "no", "0"):
            return False
        print("输入无效，请输入 y 或 n。")


# 函数说明:
# 参数：无
# 返回：headers 字典
def input_headers_zidian() -> Dict[str, str]:
    headers_zidian: Dict[str, str] = {}
    print("可选：添加自定义 header（直接回车结束）")
    while True:
        key_yuanshi = input_wenben("header key: ")
        if key_yuanshi == "":
            break
        val_yuanshi = input_wenben("header value: ")
        if val_yuanshi == "":
            print("header value 为空，已忽略。")
            continue
        headers_zidian[key_yuanshi] = val_yuanshi
    return headers_zidian


# 函数说明:
# 参数：guize_zidian 规则字典
# 返回：无
def add_lujing_guize(path_wenjian: str, port_jianting: str, yuming_pipei: str) -> None:
    rules_guize = load_lujing_guize(path_wenjian)
    print("\n=== 添加规则 ===")
    while True:
        path_yuanshi = input_wenben("请输入 path（示例: api/v1，禁止空或 /）: ")
        path_guilv = path_yuanshi.lstrip("/")
        if path_guilv in ("", "/"):
            print("path 不能为空，也不能是 /。")
            continue
        if path_guilv in rules_guize:
            print("该 path 已存在，请更换。")
            continue
        break

    while True:
        target_yuanshi = input_wenben("请输入 target（示例: 127.0.0.1:8000）: ")
        if target_yuanshi == "":
            print("target 不能为空。")
            continue
        break

    wss_kaiguan = input_wss_kaiguan()
    headers_zidian = input_headers_zidian()

    rules_guize[path_guilv] = {
        "path": path_guilv,
        "target": target_yuanshi,
        "websocket": wss_kaiguan,
        "headers": headers_zidian,
    }
    if save_lujing_guize(path_wenjian, port_jianting, yuming_pipei, rules_guize):
        print(f"添加成功: /{path_guilv}（已写入: {path_wenjian}）")
        apply_nginx_peizhi(path_wenjian)


# 函数说明:
# 参数：guize_zidian 规则字典
# 返回：无
def delete_lujing_guize(path_wenjian: str, port_jianting: str, yuming_pipei: str) -> None:
    rules_guize = load_lujing_guize(path_wenjian)
    rules_liebiao = sort_lujingguize_liebiao(rules_guize)
    if not rules_liebiao:
        print("暂无可删除规则。")
        return

    print("\n=== 删除规则 ===")
    print_lujingguize_liebiao(rules_liebiao)
    while True:
        choice_yuanshi = input_wenben("输入要删除的序号（回车取消）: ")
        if choice_yuanshi == "":
            print("已取消删除。")
            return
        if not choice_yuanshi.isdigit():
            print("请输入有效数字序号。")
            continue
        choice_xuhao = int(choice_yuanshi)
        if choice_xuhao < 1 or choice_xuhao > len(rules_liebiao):
            print("序号超出范围。")
            continue

        path_mubiao = rules_liebiao[choice_xuhao - 1]["path"]
        rules_guize.pop(path_mubiao, None)
        if save_lujing_guize(path_wenjian, port_jianting, yuming_pipei, rules_guize):
            print(f"删除成功: /{path_mubiao}（已写入: {path_wenjian}）")
            apply_nginx_peizhi(path_wenjian)
        return


# 函数说明:
# 参数：规则文件信息
# 返回：无
def show_dangeguize_caidan(info_wenjian: dict) -> None:
    path_wenjian = str(info_wenjian["filepath"])
    port_jianting = str(info_wenjian["port"])
    yuming_pipei = str(info_wenjian["domain"])

    while True:
        print(f"\n当前规则: {format_yuming_shuchu(yuming_pipei)}:{port_jianting}")
        print("1) 打印规则列表")
        print("2) 添加规则")
        print("3) 删除规则")
        print("0) 返回上级菜单")

        choice_caibu = input_wenben("请选择菜单项: ")
        if choice_caibu == "1":
            rules_guize = load_lujing_guize(path_wenjian)
            print_lujingguize_liebiao(sort_lujingguize_liebiao(rules_guize))
            continue
        if choice_caibu == "2":
            add_lujing_guize(path_wenjian, port_jianting, yuming_pipei)
            continue
        if choice_caibu == "3":
            delete_lujing_guize(path_wenjian, port_jianting, yuming_pipei)
            continue
        if choice_caibu == "0":
            return
        print("无效选择，请重试。")


# 函数说明:
# 参数：无
# 返回：无
def print_guizewenjian_liebiao(wenjian_liebiao: List[dict]) -> None:
    print("\n=== 规则文件列表 ===")
    if not wenjian_liebiao:
        print("暂无规则文件。")
        return
    for index_xuhao, info_wenjian in enumerate(wenjian_liebiao, start=1):
        domain_shuchu = format_yuming_shuchu(str(info_wenjian["domain"]))
        print(
            f"{index_xuhao}) {info_wenjian['filename']} -> {domain_shuchu}:{info_wenjian['port']}"
        )


# 函数说明:
# 参数：无
# 返回：无
def add_guizewenjian() -> None:
    duankou_jianting = input_duankou()
    yuming_pipei = input_yuming()

    wenjian_ming = f"{RULE_PREFIX_PEZHI}{duankou_jianting}.conf"
    path_wenjian = os.path.join(CONF_DIR_PEZHI, wenjian_ming)
    if os.path.exists(path_wenjian):
        print(f"规则文件已存在: {path_wenjian}")
        return

    if save_lujing_guize(path_wenjian, duankou_jianting, yuming_pipei, {}):
        print(f"创建成功: {path_wenjian}")
        apply_nginx_peizhi(path_wenjian)


# 函数说明:
# 参数：无
# 返回：无
def show_zhucaidan() -> None:
    print(f"当前规则目录: {CONF_DIR_PEZHI}")
    print(f"当前 nginx 命令: {NGINX_BIN_PEZHI}")

    while True:
        wenjian_liebiao = load_guizewenjian_liebiao()
        print_guizewenjian_liebiao(wenjian_liebiao)
        print("0) 添加规则")
        print("q) 退出")
        choice_caibu = input_wenben("请输入任务0为添加规则,其他数字为进入规则: ")

        if choice_caibu == "0":
            add_guizewenjian()
            continue
        if choice_caibu.lower() in ("q", "quit", "exit"):
            print("程序已退出。")
            return
        if not choice_caibu.isdigit():
            print("输入无效，请输入数字序号。")
            continue
        choice_xuhao = int(choice_caibu)
        if choice_xuhao < 1 or choice_xuhao > len(wenjian_liebiao):
            print("序号超出范围。")
            continue
        show_dangeguize_caidan(wenjian_liebiao[choice_xuhao - 1])


# 函数说明:
# 参数：无
# 返回：无
def start_chengxu() -> None:
    ensure_moren_guizewenjian()
    show_zhucaidan()


if __name__ == "__main__":
    start_chengxu()

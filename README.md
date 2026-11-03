
## 配置安装方法

```
   git clone https://gitee.com/keeferwu/pi-config ~/.pi/agent
```

## pi 命令补全

```
   sudo cp pi-completion /usr/share/bash-completion/completions/pi
   sudo chown root:root /usr/share/bash-completion/completions/pi
```

## 安装/卸载/更新扩展

```
pi install <extensions>
pi uninstall <extensions>
pi update --extensions
```

## 查看安装的扩展： pi list

```
  npm:pi-open-tui
  npm:pi-web-search
  npm:pi-lens
  npm:pi-cache-optimizer
  npm:context-mode
  npm:@dietrichgebert/ponytail
  npm:@narumitw/pi-plan-mode
  npm:@juicesharp/rpiv-todo
  npm:@juicesharp/rpiv-ask-user-question
  npm:@gotgenes/pi-permission-system
  npm:@gotgenes/pi-subagents
```

## 查看安装的mcp：pi mcp list

```
exa: connected, 2 tools (direct, global)
context7: connected, 2 tools (direct, global)
searchcode: connected, 7 tools (direct, global)
```

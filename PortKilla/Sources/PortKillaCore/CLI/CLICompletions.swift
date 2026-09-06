import Foundation

/// Static shell completions: the command set is small enough to spell out.
/// `portkilla completions zsh > ~/.zfunc/_portkilla` (or let the cask do it).
public enum CLICompletions {
    public static let commands = ["list", "kill", "free", "wait", "open", "history", "whois", "whoami", "free-port", "schema", "doctor", "agent-docs", "mcp", "completions", "version", "help"]

    public static func script(for shell: String) -> String? {
        switch shell {
        case "zsh": return zsh
        case "bash": return bash
        case "fish": return fish
        default: return nil
        }
    }

    private static let zsh = """
    #compdef portkilla
    local -a commands
    commands=(
      'list:list listening ports (with owning agent)'
      'kill:kill everything on a port'
      'free:kill, exit 0 if already free'
      'wait:block until a port is free'
      'open:open localhost:<port> in the browser'
      'history:recent kills, who started and who stopped them'
      'whois:who started what is on a port, and why PortKilla thinks so'
      'whoami:how the friendly-fire guard identifies you'
      'free-port:first free port in a range'
      'schema:JSON output contracts'
      'doctor:environment and scanner diagnostics'
      'agent-docs:snippet for CLAUDE.md / AGENTS.md'
      'completions:shell completion script'
      'version:print version'
      'help:usage'
    )
    if (( CURRENT == 2 )); then
      _describe 'command' commands
      return
    fi
    case $words[2] in
      list) _arguments '--json' '--mine' '--unowned' '--orphaned' '--agent[agent name]:name' ;;
      kill|free) _arguments '--force' '-9' '--dry-run' '--json' '--orphaned' '--pid[process id]:pid' ;;
      wait) _arguments '--json' '--timeout[seconds]:seconds' ;;
      free-port) _arguments '--json' '--prefer[port]:port' '--range[A-B]:range' ;;
      schema) _values 'command' list kill whois whoami wait history version doctor agents free-port ;;
      history) _arguments '--json' '--port[port]:port' '--limit[count]:count' ;;
      whois) _arguments '--json' '--pid[process id]:pid' ;;
      doctor) _arguments '--json' '--agents' ;;
      whoami|version) _arguments '--json' ;;
      mcp) _arguments '--setup[registration for an agent]:agent:(claude cursor codex)' ;;
      completions) _values 'shell' zsh bash fish ;;
    esac
    """

    private static let bash = """
    _portkilla() {
      local cur="${COMP_WORDS[COMP_CWORD]}"
      if [ "$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=( $(compgen -W "\(commands.joined(separator: " "))" -- "$cur") )
        return
      fi
      case "${COMP_WORDS[1]}" in
        list) COMPREPLY=( $(compgen -W "--json --mine --unowned --orphaned --agent" -- "$cur") ) ;;
        kill|free) COMPREPLY=( $(compgen -W "--force -9 --dry-run --json --orphaned --pid" -- "$cur") ) ;;
        wait) COMPREPLY=( $(compgen -W "--json --timeout" -- "$cur") ) ;;
        free-port) COMPREPLY=( $(compgen -W "--json --prefer --range" -- "$cur") ) ;;
        schema) COMPREPLY=( $(compgen -W "list kill whois whoami wait history version doctor agents free-port" -- "$cur") ) ;;
        history) COMPREPLY=( $(compgen -W "--json --port --limit" -- "$cur") ) ;;
        whois) COMPREPLY=( $(compgen -W "--json --pid" -- "$cur") ) ;;
        doctor) COMPREPLY=( $(compgen -W "--json --agents" -- "$cur") ) ;;
        whoami|version) COMPREPLY=( $(compgen -W "--json" -- "$cur") ) ;;
        mcp) COMPREPLY=( $(compgen -W "--setup claude cursor codex" -- "$cur") ) ;;
        completions) COMPREPLY=( $(compgen -W "zsh bash fish" -- "$cur") ) ;;
      esac
    }
    complete -F _portkilla portkilla
    """

    private static let fish = """
    complete -c portkilla -f
    \(commands.map { "complete -c portkilla -n '__fish_use_subcommand' -a \($0)" }.joined(separator: "\n"))
    complete -c portkilla -n '__fish_seen_subcommand_from list' -l json -l mine -l unowned -l orphaned -l agent
    complete -c portkilla -n '__fish_seen_subcommand_from kill free' -l force -l dry-run -l json -l orphaned -l pid
    complete -c portkilla -n '__fish_seen_subcommand_from wait' -l json -l timeout
    complete -c portkilla -n '__fish_seen_subcommand_from free-port' -l json -l prefer -l range
    complete -c portkilla -n '__fish_seen_subcommand_from schema' -a 'list kill whois whoami wait history version doctor agents free-port'
    complete -c portkilla -n '__fish_seen_subcommand_from history' -l json -l port -l limit
    complete -c portkilla -n '__fish_seen_subcommand_from whois' -l json -l pid
    complete -c portkilla -n '__fish_seen_subcommand_from doctor' -l json -l agents
    complete -c portkilla -n '__fish_seen_subcommand_from whoami version' -l json
    complete -c portkilla -n '__fish_seen_subcommand_from mcp' -l setup -a 'claude cursor codex'
    complete -c portkilla -n '__fish_seen_subcommand_from completions' -a 'zsh bash fish'
    """
}

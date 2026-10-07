function cy --description 'Start Claude Code with permission prompts bypassed'
    command claude --dangerously-skip-permissions $argv
end

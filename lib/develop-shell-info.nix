{ bundleRelease, buildEnv }: 
args_@{ name } :
buildEnv ({
  name = "${name}-developShellInfo";
  paths = [];
  postBuild = ''
    # Export information about this particular workspace / bundle.
    cat <<EOT >> $out/workspace_info.sh
    export NIX_BUNDLE_TAG=$(cat ${bundleRelease})
    export NIX_BUNDLE_TYPE=${name}
    EOT

    # Change the prompt, refering to the variables from the workspace info, such that people could shorten them
    # or modify them once inside the prompt without overwriting PS1.
    cat <<EOT >> $out/change_shell_prompt.sh
    if [ -z "\$NIX_NO_DEVELOP_PROMPT" ];
    then
    export PS1="\[\033[01;36m\]\\\$NIX_BUNDLE_TAG#\\\$NIX_BUNDLE_TYPE\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ "
    fi
    EOT
  '';
})

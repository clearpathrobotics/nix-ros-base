{ buildEnv }: 
args_@{ name } :
buildEnv ({
  name = "${name}-developShellPreventMixing";
  paths = [];
  postBuild = ''
    cat <<EOT >> $out/guard.sh
    if [ ! -z "\$ROS_DISTRO" ];
    then
      echo -e "\033[0;31mYou already had a bundle sourced, you cannot source two bundles. Exiting this shell in 5 seconds.\033[0m"
      sleep 5
      exit 1
    fi
    EOT
  '';
})

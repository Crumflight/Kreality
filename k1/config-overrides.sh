#!/bin/sh

CONFIG_OVERRIDES="/usr/data/Crumflight/k1/config-overrides.py"

setup_git_repo() {
    if [ -d /usr/data/Crumflight-overrides ]; then
        cd /usr/data/Crumflight-overrides
        if ! git status > /dev/null 2>&1; then
          if [ $(ls | wc -l) -gt 0 ]; then
            cd - > /dev/null
            mv /usr/data/Crumflight-overrides /usr/data/Crumflight-overrides.$$
          else
            cd - > /dev/null
            rm -rf /usr/data/Crumflight-overrides/
          fi
        fi
    fi

    git clone "https://$GITHUB_USERNAME:$GITHUB_TOKEN@github.com/$GITHUB_USERNAME/$GITHUB_REPO.git" /usr/data/Crumflight-overrides || exit $?
    cd /usr/data/Crumflight-overrides || exit $?
    git config user.name "$GITHUB_USERNAME" || exit $?
    git config user.email "$EMAIL_ADDRESS" || exit $?

    # is this a brand new repo, setup a simple readme as the first commit
    if [ $(ls | wc -l) -eq 0 ]; then
        echo "# simple af Crumflight-overrides" >> README.md
        echo "https://github.com/Crumflight/creality/wiki/K1-Stock-Mainboard-Less-Creality#git-backups-for-configuration-overrides" >> README.md
        git add README.md || exit $?
        git commit -m "initial commit" || exit $?
        git branch -M main || exit $?
        git push -u origin main || exit $?
    fi

    # the rest of the script will actually push the changes if needed
    if [ -d /usr/data/Crumflight-overrides.$$ ]; then
        mv /usr/data/Crumflight-overrides.$$/* /usr/data/Crumflight-overrides/
        rm -rf /usr/data/Crumflight-overrides.$$
    fi
}

override_json_file() {
    local file=$1

    if [ "$file" = "guppyconfig.json" ] && [ -f /usr/data/Crumflight-backups/guppyconfig.json ] && [ -f /usr/data/guppyscreen/guppyconfig.json ]; then
        for entry in display_brightness invert_z_icon display_sleep_sec theme; do
            stock_value=$(jq -cr ".$entry" /usr/data/Crumflight-backups/guppyconfig.json)
            new_value=$(jq -cr ".$entry" /usr/data/guppyscreen/guppyconfig.json)
            # you know what its not an actual json file its just the properties we support updating
            if [ "$stock_value" != "null" ] && [ "$new_value" != "null" ] && [ "$stock_value" != "$new_value" ]; then
                echo "$entry=$new_value" >> /usr/data/Crumflight-overrides/guppyconfig.json
            fi
        done
        if [ -f /usr/data/Crumflight-overrides/guppyconfig.json ]; then
            echo "INFO: Saving overrides to /usr/data/Crumflight-overrides/guppyconfig.json"
            sync
        fi
    else
        echo "INFO: Overrides not supported for $file"
        return 0
    fi
}

override_file() {
    local file=$1

    if [ -L /usr/data/printer_data/config/$file ]; then
        echo "INFO: Overrides not supported for $file"
        return 0
    fi

    overrides_file="/usr/data/Crumflight-overrides/$file"
    original_file="/usr/data/Crumflight/k1/$file"
    updated_file="/usr/data/printer_data/config/$file"
    
    if [ -f "/usr/data/Crumflight-backups/$file" ]; then
        original_file="/usr/data/Crumflight-backups/$file"
    elif [ "$file" = "printer.cfg" ] || [ "$file" = "beacon.conf" ] || [ "$file" = "cartographer.conf" ] || [ "$file" = "moonraker.conf" ] || [ "$file" = "start_end.cfg" ] || [ "$file" = "useful_macros.cfg" ] || [ "$file" = "fan_control.cfg" ]; then
        # for printer.cfg, useful_macros.cfg, start_end.cfg, fan_control.cfg and moonraker.conf - there must be an Crumflight-backups file
        echo "INFO: Overrides not supported for $file"
        return 0
    elif [ "$file" = "guppyscreen.cfg" ]; then
        echo "INFO: Overrides not supported for $file"
        return 0
    elif [ ! -f "/usr/data/Crumflight/k1/$file" ]; then
        echo "INFO: Backing up /usr/data/printer_data/config/$file ..."
        cp  /usr/data/printer_data/config/$file /usr/data/Crumflight-overrides/
        return 0
    fi
    $CONFIG_OVERRIDES --original "$original_file" --updated "$updated_file" --overrides "$overrides_file" || exit $?

    # we renamed the SENSORLESS_PARAMS to hide it
    if [ -f /usr/data/Crumflight-overrides/sensorless.cfg ]; then
      sed -i 's/gcode_macro SENSORLESS_PARAMS/gcode_macro _SENSORLESS_PARAMS/g' /usr/data/Crumflight-overrides/sensorless.cfg
    fi

    if [ "$file" = "printer.cfg" ]; then
      saves=false
      while IFS= read -r line; do
        if [ "$line" = "#*# <---------------------- SAVE_CONFIG ---------------------->" ]; then
          saves=true
          echo "" > /usr/data/Crumflight-overrides/printer.cfg.save_config
          echo "INFO: Saving save config state to /usr/data/Crumflight-overrides/printer.cfg.save_config"
        fi
        if [ "$saves" = "true" ]; then
          echo "$line" >> /usr/data/Crumflight-overrides/printer.cfg.save_config
        fi
      done < "$updated_file"
    fi
}

# make sure we are outside of the /usr/data/Crumflight-overrides directory
cd /root/

if [ "$1" = "--repo" ] || [ "$1" = "--clean-repo" ]; then
  if [ -n "$GITHUB_USERNAME" ] && [ -n "$EMAIL_ADDRESS" ] && [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_REPO" ]; then
        if [ "$1" = "--clean-repo" ] && [ -d /usr/data/Crumflight-overrides ]; then
          echo "INFO: Deleting existing /usr/data/Crumflight-overrides"
          rm -rf /usr/data/Crumflight-overrides
        fi
        setup_git_repo
    else
        echo "You must define these environment variables:"
        echo "GITHUB_USERNAME"
        echo "EMAIL_ADDRESS"
        echo "GITHUB_TOKEN"
        echo "GITHUB_REPO"
        echo ""
        echo "https://github.com/Crumflight/creality/wiki/K1-Stock-Mainboard-Less-Creality#git-backups-for-configuration-overrides"
        exit 1
    fi
else
  # there will be no support for generating Crumflight-overrides unless you have done a factory reset
  if [ -f /usr/data/Crumflight-backups/printer.factory.cfg ]; then
      # the Crumflight-backups do not need .Crumflight extension, so this is to fix backwards compatible
      if [ -f /usr/data/Crumflight-backups/printer.Crumflight.cfg ]; then
          mv /usr/data/Crumflight-backups/printer.Crumflight.cfg /usr/data/Crumflight-backups/printer.cfg
      fi
  fi

  if [ ! -f /usr/data/Crumflight-backups/printer.cfg ]; then
      echo "ERROR: /usr/data/Crumflight-backups/printer.cfg missing"
      exit 1
  fi

  if [ -f /usr/data/Crumflight-overrides.cfg ]; then
      echo "ERROR: /usr/data/Crumflight-overrides.cfg exists!"
      exit 1
  fi

  mkdir -p /usr/data/Crumflight-overrides

  # in case we changed config and no longer need an override file, we should delete all
  # all the config files there.
  rm /usr/data/Crumflight-overrides/*.cfg 2> /dev/null
  rm /usr/data/Crumflight-overrides/*.conf 2> /dev/null
  rm /usr/data/Crumflight-overrides/*.json 2> /dev/null
  if [ -f /usr/data/Crumflight-overrides/printer.cfg.save_config ]; then
    rm /usr/data/Crumflight-overrides/printer.cfg.save_config
  fi
  if [ -f /usr/data/Crumflight-overrides/moonraker.secrets ]; then
    rm /usr/data/Crumflight-overrides/moonraker.secrets
  fi

  # special case for moonraker.secrets
  if [ -f /usr/data/printer_data/moonraker.secrets ] && [ -f /usr/data/Crumflight/k1/moonraker.secrets ]; then
      diff /usr/data/printer_data/moonraker.secrets /usr/data/Crumflight/k1/moonraker.secrets > /dev/null
      if [ $? -ne 0 ]; then
          echo "INFO: Backing up /usr/data/printer_data/moonraker.secrets..."
          cp /usr/data/printer_data/moonraker.secrets /usr/data/Crumflight-overrides/
      fi
  fi

  files=$(find /usr/data/printer_data/config/ -maxdepth 1 ! -name 'printer-*.cfg' -a ! -name ".printer.cfg" -a -name "*.cfg" -o -name "*.conf")
  for file in $files; do
    file=$(basename $file)
    override_file $file
  done

  # we will support some limited overrides of values in guppyconfig.json
  override_json_file guppyconfig.json
fi

cd /usr/data/Crumflight-overrides
if git status > /dev/null 2>&1; then
    echo
    echo "INFO: /usr/data/Crumflight-overrides is a git repository"

    # special handling for moonraker.secrets, we do not want to source control this
    # file for fear of leaking credentials
    if [ ! -f .gitignore ]; then
      echo "moonraker.secrets" > .gitignore
    elif ! grep -q "moonraker.secrets" .gitignore; then
      echo "moonraker.secrets" >> .gitignore
    fi

    # make sure we remove any versioned file
    git rm --cached moonraker.secrets 2> /dev/null

    status=$(git status)
    echo "$status" | grep -q "nothing to commit, working tree clean"
    if [ $? -eq 0 ]; then
        echo "INFO: No changes in git repository"
    else
        echo "INFO: Outstanding changes - pushing them to remote repository"
        branch=$(git rev-parse --abbrev-ref HEAD)
        git add --all || exit $?
        git commit -m "Crumflight override changes" || exit $?
        git push -u origin $branch || exit $?
    fi
fi

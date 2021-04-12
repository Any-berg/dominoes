#!/bin/sh
#
# This test hook verifies ALL Dockerfiles currently in the workspace by
#  1) linting them,
#  2) building the images, and
#  3) running in-container tests if any are specified - and if image was built.
#
# In a pre-commit, linting is restricted to staged additions and modifications;
# likewise, builds are limited to images that have any build context changes.
# Untracked files are assumed to have been stashed away.

staged_files="$1"

context=$(git config dockerfile.buildcontext) || unset context
cid=".cid"
errors=0

all_files=$(find . -path ./.git -prune -o ! -path . -print | sed "s|^\./||")
i=0
while IFS= read -r file; do
  if [[ ${file##*/} == "Dockerfile" ]]; then

    # lint only the Dockerfiles that are staged to be either added or modified
    if [ -z "$staged_files" ] ||
       [[ $staged_files =~ ^[AM][[:space:]]"$file" ]]; then
      echo "Linting '$file'"
      docker run --rm -i hadolint/hadolint < $file || ((errors=errors+1))
    fi

    # build only undeleted Dockerfiles that have possible build context changes
    if [ -z "$staged_files" ] ||
       [[ ! $staged_files =~ ^"D"[[:space:]]"$file" &&
          $staged_files =~ [[:space:]]"${context-${file%${file##*/}}}" ]]; then
      tag="pre-commit:$(date +%s)$i"
      echo "Building '$file' as '$tag'"
      [[ $file == *"/"* ]] && path="${file%/*}" || path="."
      docker build $path -f $file -t $tag > /dev/null || ((errors=errors+1))

      # run in-container tests if any are provided (and if the image was built)
      tests="${file%${file##*/}}test-entrypoint.sh"
      if [ -e $tests ] && ! [ -z "$(docker images $tag --format _)" ]; then
        echo "Running '$tests' in container"
        docker run --volume=$(pwd)/$tests:/${tests##*/} \
                   --entrypoint /${tests##*/} \
                   --cidfile=$cid $tag > /dev/null || ((errors=errors+1))

        # remove container and corresponding cid file
        docker rm $(cat $cid) > /dev/null
        rm $cid
      fi

      # remove image (if it was built) and increment the index
      docker rmi $tag > /dev/null 2>&1
      i=$((i+1))
    fi
  fi
done <<< "$all_files"

exit $errors

# https://codeinthehole.com/tips/tips-for-using-a-git-pre-commit-hook/
# https://codingkilledthecat.wordpress.com/2012/04/27/git-stash-pop-considered-harmful/
# https://stackoverflow.com/questions/43770520/how-to-specify-default-merge-strategy-on-git-stash-pop
# https://stackoverflow.com/questions/2412450/git-pre-commit-hook-changed-added-files
# https://medium.com/sweetmeat/remove-unwanted-unstaged-changes-in-tracked-files-from-a-git-repository-d41c4f64a251
# https://stackoverflow.com/questions/644714/what-regex-can-match-sequences-of-the-same-character
# https://stackoverflow.com/questions/4210042/how-to-exclude-a-directory-in-find-command
# https://stackoverflow.com/questions/2596462/how-to-strip-leading-in-unix-find
# https://stackoverflow.com/questions/13525004/how-to-exclude-this-current-dot-folder-from-find-type-d

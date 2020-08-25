#!/bin/sh
# 
# This pre-commit hook verifies ALL tracked Dockerfiles in the repository by
#  1) linting them if they are staged to be either added or modified,
#  2) building the images if there are possible build context changes, and
#  3) running in-container tests if any are specified - and if image was built.
#
# Untracked and unstaged files are stashed away during verification in order
# to abort incomplete commits (like a Dockerfile without the needed entrypoint);
# any unstaged changes in staged files cause conflicts that need to be resolved.

staged_files=$(git diff --cached --name-status)
[ -z "$staged_files" ] && exit 0

grep -lRE "^[<=>]{7}" . && {
  echo "Aborting until merge conflicts in above files are manually resolved"
  exit 1
}

echo "Stashing away untracked and unstaged files"
git stash push --all --keep-index > /dev/null
[ $? -eq 0 ] || exit 1

context=$(git config dockerfile.buildcontext) || unset context
cid=".cid"
errors=0

tracked_or_staged_files=$(git ls-files)
i=0
while IFS= read -r file; do
  if [[ ${file##*/} == "Dockerfile" ]]; then

    # lint only the Dockerfiles that are staged to be either added or modified
    if [[ $staged_files =~ [AM][[:space:]]"$file" ]]; then
      echo "Linting '$file'"
      docker run --rm -i hadolint/hadolint < $file || ((errors=errors+1))
    fi

    # build only undeleted Dockerfiles that have possible build context changes
    if ! [[ $staged_files =~ "D"[[:space:]]"$file" ]] && 
        [[ $staged_files =~ [[:space:]]"${context-${file%${file##*/}}}" ]]; then
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
done <<< "$tracked_or_staged_files"

echo "Restoring untracked and unstaged files from stash"
git stash pop > /dev/null

unmerged_files=$(git diff --name-only --diff-filter=U)
if ! [ -z "$unmerged_files" ]; then
  echo "Resolving conflicts caused by unstaged changes in staged files"
  while IFS= read -r file; do
    # stage original file (ours) and overlay extracted unstaged changes (theirs)
    perl -0777 -pe 's/^<{7}[^\n]+\n(.*?)\n={7}\n(.*?)\n>{7}[^\n]+/\2/gsm' \
        $file > $file.theirs
    git checkout --ours $file 2> /dev/null
    git add $file
    mv -f $file.theirs $file
  done <<< "$unmerged_files"
  git stash drop > /dev/null 
fi
grep -RE "^[<=>]{7}" . > /dev/null && { echo "ERROR: botched merge"; exit 1; }

[[ $errors -ne 0 ]] && { echo "Aborting commit as invalid: see above"; exit 1; }
exit 0

# https://codeinthehole.com/tips/tips-for-using-a-git-pre-commit-hook/
# https://codingkilledthecat.wordpress.com/2012/04/27/git-stash-pop-considered-harmful/
# https://stackoverflow.com/questions/43770520/how-to-specify-default-merge-strategy-on-git-stash-pop
# https://stackoverflow.com/questions/2412450/git-pre-commit-hook-changed-added-files
# https://medium.com/sweetmeat/remove-unwanted-unstaged-changes-in-tracked-files-from-a-git-repository-d41c4f64a251

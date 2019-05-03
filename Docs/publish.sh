#!/bin/ash
# Publish docs to GitHub Pages.
# Note that this script is intended to be run by GitHub Actions.
if ! (env | grep '^GITHUB_'); then
  {
    echo "This script is intended to be run by GitHub Actions."
    echo "You can run GitHub Actions locally using \`act':"
    echo "  https://github.com/nektos/act"
  } > /dev/stderr
  exit 1
fi

set -ev

b64d() {
  if command -v python > /dev/null; then
    python -m base64 -d
  else
    base64 -d
  fi
}

if [ "$GHPAGES_SSH_KEY" = "" ]; then
  {
    echo "The environment variable GHPAGES_SSH_KEY is not configured."
    echo "Configure GITHUB_TOKEN from GitHub Actions web page."
    echo "The key has to be also registered as a deploy key of the repository" \
         ", and be allowed write access."
    echo "GHPAGES_SSH_KEY has to contain a base64-encoded private key without" \
         "new lines."
  } > /dev/stderr
  exit 0
fi

echo "$GHPAGES_SSH_KEY" | b64d > /tmp/github_id
chmod 600 /tmp/github_id
export GIT_SSH_COMMAND='ssh -i /tmp/github_id -o "StrictHostKeyChecking no"'

for _ in 1 2 3; do
  # If more than an action are running simultaneously git push may fail
  # due to conflicts.  So try up to 3 times.

  git clone -b gh-pages "git@github.com:$GITHUB_REPOSITORY.git" /tmp/gh-pages
  git -C /tmp/gh-pages config user.name "$(git log -n1 --format=%cn)"
  git -C /tmp/gh-pages config user.email "$(git log -n1 --format=%ce)"

  slug="$(echo -n "$GITHUB_REF" | sed -e 's/^refs\/\(heads\|tags\)\///g')"
  [ "$slug" != "" ]
  rm -rf "/tmp/gh-pages/$slug"
  cp -r Docs/_site "/tmp/gh-pages/$slug"
  git -C /tmp/gh-pages add "/tmp/gh-pages/$slug"

  latest_version="$(git tag --sort -v:refname | head -n1)"
  tag="$(echo -n "$GITHUB_REF" | sed -e 's/^refs\/tags\///g')"
  if [ "$(git tag -l)" = "" ] || [ "$latest_version" = "$tag" ]; then
    index="$(cat "/tmp/gh-pages/$slug/index.html")"
    {
      echo -n "${index%</title>*}</title>"
      echo "<meta http-equiv=\"refresh\" content=\"0;$slug/\">"
      echo "<base href=\"$slug/\">"
      echo -n "${index#*</title>}"
    } > /tmp/gh-pages/index.html
    git -C /tmp/gh-pages add /tmp/gh-pages/index.html
  fi

  git -C /tmp/gh-pages commit \
    --allow-empty \
    -m "Publish docs from $GITHUB_SHA"

  if git -C /tmp/gh-pages push origin gh-pages; then
    break
  fi

  rm -rf /tmp/gh-pages
done

rm /tmp/github_id

mkdir -p Docs/obj/
github_user="${GITHUB_REPOSITORY%/*}"
github_repo="${GITHUB_REPOSITORY#*/}"
echo -n "https://$github_user.github.io/$github_repo/$slug/" > Docs/obj/url.txt

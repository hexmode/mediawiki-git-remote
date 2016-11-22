#!/bin/sh
called=$0
thispath="$( cd "$(dirname "$called")" ; pwd -P )"
GIT_EXEC_PATH=$(git --exec-path)

case ":${GIT_EXEC_PATH:=$thispath}:" in
    *:$thispath:*)  ;;
    *) GIT_EXEC_PATH="$thispath:$GIT_EXEC_PATH"  ;;
esac
export GIT_EXEC_PATH

case ":${PERL5LIB:=$thispath/localcpan}:" in
    *:$thispath/localcpan:*)  ;;
    *) PERL5LIB="$thispath/localcpan:$PERL5LIB"  ;;
esac

case ":${PERL5LIB:=$thispath/lib}:" in
    *:$thispath/lib:*)  ;;
    *) PERL5LIB="$thispath/lib:$PERL5LIB"  ;;
esac
export PERL5LIB
echo PERL5LIB=$PERL5LIB
echo export PERL5LIB
echo GIT_EXEC_PATH=$GIT_EXEC_PATH
echo export GIT_EXEC_PATH

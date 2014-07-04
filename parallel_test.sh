#!/bin/sh

# execute test case in parallel in a typical symfony 2 environment
echo "testing in parallel processes"

# global variables
MAXPROCS=4

# set yout test case directory here
TESTCASEDIR=./src/Acme/DemoBundle/Tests

SHARED=app/cache/shared

COUNT=0
for T in $(find $TESTCASEDIR -iname '*Test.php'); do
	COUNT=$((COUNT + 1))		
	T=`basename $T`
	STRLEN=${#T}
	STRLEN=$(($STRLEN - 4))
	T=${T:0:$STRLEN}
	TESTS="${TESTS}${T} "
done

echo $TESTS

declare -A environments

echo -n "" > $SHARED

initdb() {
	app/console doctrine:database:drop --force --env=test$1
	app/console doctrine:database:create --env=test$1
	app/console doctrine:schema:create --env=test$1
}

export -f initdb

for ((I=1; I<=$MAXPROCS; I++)); do
    echo test$I:available >> $SHARED
    ENVS="${ENVS}${I} "
done

parallel --gnu --no-notice -j$MAXPROCS initdb ::: $ENVS

export environments

for K in "${!environments[@]}"; do
    V=${environments["$K"]}
    echo "$K : $V"
done

lockenvironment() {
    exec 3<> $1 # open shared state file as fd3

    # flock state file
    flock -x 3

    declare -A ENVIRONMENTS

    while IFS= read -u 3 -r LINE
    do
        IFS=":" read -ra L <<< "$LINE"
        K=${L[0]}
        V=${L[1]}
        ENVIRONMENTS["$K"]="$V"
    done

    FREE="none"
    for K in "${!ENVIRONMENTS[@]}"; do
         V=${ENVIRONMENTS["$K"]}
         if [[ $V == "available" ]]; then
             FREE=$K
             break
         fi
    done

    if [[ $FREE == "none" ]]; then
        RUNENV="none"
        echo "no free environment found, skipping test. this should not happen"
        exit
    fi

    ENVIRONMENTS["$K"]="inuse"
    RUNENV=$K

    echo -n "" > $1
    for K in "${!ENVIRONMENTS[@]}"; do
        V=${ENVIRONMENTS["$K"]}
        echo "$K:$V" >> $1
    done

    # flock - free state file
    flock -u 3

    exec 3>&- #close fd 3
}

export -f lockenvironment

freeenvironment() {
    exec 3<> $1 # open shared state file as fd3
    # flock state file
    flock -x 3

    declare -A ENVIRONMENTS

    while IFS= read -u 3 -r LINE
    do
        #echo $LINE
        IFS=":" read -ra L <<< "$LINE"
        #for P in "${L[@]}"; do
        #    echo $P
        #done
        K=${L[0]}
        V=${L[1]}
        ENVIRONMENTS["$K"]="$V"
    done

    ENVIRONMENTS["$RUNENV"]="available"

    echo -n "" > $1
    for K in "${!ENVIRONMENTS[@]}"; do
        V=${ENVIRONMENTS["$K"]}
        echo "$K:$V" >> $1
    done

    # flock - free state file
    flock -u 3

    exec 3>&- #close fd 3
}

export -f freeenvironment

dotest() {
    echo $1 # the test case
    #echo $2 # the shared state file

    lockenvironment $2

    if [[ $RUNENV == "none" ]]; then
        echo "no free environment found, skipping test. this should not happen"
        exit
    fi

    echo "running phpunit in env $RUNENV"

    ##sleep 1
    # do the test in the free environment
    PHPUNIT_PARALLEL_TEST_ENVIRONMENT=$RUNENV
    export PHPUNIT_PARALLEL_TEST_ENVIRONMENT
    echo $PHPUNIT_PARALLEL_TEST_ENVIRONMENT
    bin/phpunit -c app/ --filter=$1

    # free the run environment
    echo "freeing environment $RUNENV"
    freeenvironment $2

    echo "--------------------------------------------------"
}

export -f dotest

parallel --gnu --no-notice -j$MAXPROCS dotest ::: $TESTS ::: $SHARED

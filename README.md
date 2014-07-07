parallel-test
=============

Allow parallel execution of test cases in Symfony2 applications

Requirements
------------

- gnu parallel
- flock

Usage
-----

- copy the script to your symfony directory (optional)
- change the MAXPROCS variable according to your hardware configuration
- point the TESTCASEDIR variable to the test case directory
- configure environments test1, test2, ... , test{MAXPROCS}
- run script

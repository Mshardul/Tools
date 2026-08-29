#!/bin/bash
# Replaces itself with sleep so a SIGTERM to the child reaches sleep directly.
# Used for the cancellation test.
exec sleep 60

#!/bin/bash
# Cancellation-test fixture: exec's sleep so a SIGTERM to the child reaches sleep directly.
exec sleep 60

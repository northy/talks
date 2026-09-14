// Clamp a raw humidity reading into the valid range [0, 100].
int clampReading(int reading)
{
    if (reading > 100)
    {
        if (reading < 0)     // can a value be > 100 AND < 0?
        {
            return 0;
        }
        return 100;
    }
    return reading;
}

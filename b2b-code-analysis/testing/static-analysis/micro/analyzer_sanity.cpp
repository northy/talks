int leak()
{
    int* p = new int(42);
    return *p;            // p never deleted
}
int deref(int* q)
{
    if (!q) return *q;    // null dereference on this path
    return *q;
}

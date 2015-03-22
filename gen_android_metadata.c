#define _XOPEN_SOURCE 500
#include <ftw.h>

#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <stdint.h>


#include <sys/types.h>
#include <attr/xattr.h>
#include <linux/capability.h>
#include <linux/xattr.h>

static struct vfs_cap_data cap_data;
static uint64_t cap;
static ssize_t r;
static char buff[2048];

static int read_xattrs(const char *fpath, const struct stat *sb, int typeflag, struct FTW *ftwbuf)
{
    printf("set_metadata(\"/%s\"", fpath);

    // caps
    r = lgetxattr(fpath, XATTR_NAME_CAPS, &cap_data, sizeof(cap_data));
    if(r == sizeof(cap_data))
    {
        cap = cap_data.data[0].permitted;
        cap |= ((uint64_t)cap_data.data[1].permitted) << 32;
    }
    else
        cap = 0;

    printf(", \"capabilities\", 0x%x", cap);

    // selinux
    buff[0] = 0;
    r = lgetxattr(fpath, XATTR_NAME_SELINUX, buff, sizeof(buff));
    if(r > 0)
        printf(", \"selabel\", \"%s\"", buff);

    printf(");\n");
    return 0;
}

int main(int argc, char **argv)
{
    if(argc != 2)
    {
        printf("Usage: %s DIR\n", argv[0]);
        return -1;
    }

    return nftw(argv[1], read_xattrs, 30, FTW_PHYS);
}

#import "AntiDetection.h"
#import <UIKit/UIKit.h>
#import <sys/sysctl.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <string.h>
#import <sys/stat.h>
#import <stdarg.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <mach/vm_map.h>
#import <mach/mach.h>

// 架构适配（arm64 永远为 64 位）
#ifndef LC_SEGMENT_ARCH_DEPENDENT
#define LC_SEGMENT_ARCH_DEPENDENT LC_SEGMENT_64
#endif

// fishhook 结构
struct rebinding {
    const char *name;
    void *replacement;
    void **replaced;
};

struct rebindings_entry {
    struct rebinding *rebindings;
    size_t rebindings_nel;
    struct rebindings_entry *next;
};

// fishhook 实现
static struct rebindings_entry *_rebindings_head;

static int prepend_rebindings(struct rebindings_entry **rebindings_head,
                              struct rebinding rebindings[],
                              size_t nel) {
    struct rebindings_entry *new_entry = (struct rebindings_entry *) malloc(sizeof(struct rebindings_entry));
    if (!new_entry) return -1;
    new_entry->rebindings = (struct rebinding *) malloc(sizeof(struct rebinding) * nel);
    if (!new_entry->rebindings) {
        free(new_entry);
        return -1;
    }
    memcpy(new_entry->rebindings, rebindings, sizeof(struct rebinding) * nel);
    new_entry->rebindings_nel = nel;
    new_entry->next = *rebindings_head;
    *rebindings_head = new_entry;
    return 0;
}

static void perform_rebinding_with_section(struct rebindings_entry *rebindings,
                                           struct section_64 *section,
                                           intptr_t slide,
                                           struct nlist_64 *symtab,
                                           char *strtab,
                                           uint32_t *indirect_symtab) {
    uint32_t *indirect_symbol_indices = indirect_symtab + section->reserved1;
    void **indirect_symbol_bindings = (void **)((uintptr_t)slide + section->addr);

    for (uint i = 0; i < section->size / sizeof(void *); i++) {
        uint32_t symtab_index = indirect_symbol_indices[i];
        if (symtab_index == INDIRECT_SYMBOL_ABS || symtab_index == INDIRECT_SYMBOL_LOCAL ||
            symtab_index == (INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS)) continue;

        uint32_t strtab_offset = symtab[symtab_index].n_un.n_strx;
        char *symbol_name = strtab + strtab_offset;
        bool symbol_name_longer_than_1 = symbol_name[0] && symbol_name[1];
        struct rebindings_entry *cur = rebindings;
        while (cur) {
            for (uint j = 0; j < cur->rebindings_nel; j++) {
                if (symbol_name_longer_than_1 && strcmp(&symbol_name[1], cur->rebindings[j].name) == 0) {
                    if (cur->rebindings[j].replaced != NULL &&
                        indirect_symbol_bindings[i] != cur->rebindings[j].replacement)
                        *(cur->rebindings[j].replaced) = indirect_symbol_bindings[i];

                    kern_return_t err = vm_protect(mach_task_self(),
                                                   (uintptr_t)indirect_symbol_bindings,
                                                   section->size,
                                                   0,
                                                   VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
                    if (err == KERN_SUCCESS) {
                        indirect_symbol_bindings[i] = cur->rebindings[j].replacement;
                    }
                    goto symbol_loop;
                }
            }
            cur = cur->next;
        }
    symbol_loop:;
    }
}

static void rebind_symbols_for_image(struct rebindings_entry *rebindings,
                                     const struct mach_header *header,
                                     intptr_t slide) {
    Dl_info info;
    if (dladdr(header, &info) == 0) return;

    struct segment_command_64 *cur_seg_cmd;
    struct segment_command_64 *linkedit_segment = NULL;
    struct symtab_command *symtab_cmd = NULL;
    struct dysymtab_command *dysymtab_cmd = NULL;

    uintptr_t cur = (uintptr_t)header + sizeof(struct mach_header_64);
    for (uint i = 0; i < header->ncmds; i++, cur += cur_seg_cmd->cmdsize) {
        cur_seg_cmd = (struct segment_command_64 *)cur;
        if (cur_seg_cmd->cmd == LC_SEGMENT_ARCH_DEPENDENT) {
            if (strcmp(cur_seg_cmd->segname, SEG_LINKEDIT) == 0) {
                linkedit_segment = cur_seg_cmd;
            }
        } else if (cur_seg_cmd->cmd == LC_SYMTAB) {
            symtab_cmd = (struct symtab_command *)cur_seg_cmd;
        } else if (cur_seg_cmd->cmd == LC_DYSYMTAB) {
            dysymtab_cmd = (struct dysymtab_command *)cur_seg_cmd;
        }
    }

    if (!symtab_cmd || !dysymtab_cmd || !linkedit_segment ||
        !dysymtab_cmd->nindirectsyms) return;

    uintptr_t linkedit_base = (uintptr_t)slide + linkedit_segment->vmaddr - linkedit_segment->fileoff;
    struct nlist_64 *symtab = (struct nlist_64 *)(linkedit_base + symtab_cmd->symoff);
    char *strtab = (char *)(linkedit_base + symtab_cmd->stroff);
    uint32_t *indirect_symtab = (uint32_t *)(linkedit_base + dysymtab_cmd->indirectsymoff);

    cur = (uintptr_t)header + sizeof(struct mach_header_64);
    for (uint i = 0; i < header->ncmds; i++, cur += cur_seg_cmd->cmdsize) {
        cur_seg_cmd = (struct segment_command_64 *)cur;
        if (cur_seg_cmd->cmd == LC_SEGMENT_ARCH_DEPENDENT) {
            if (strcmp(cur_seg_cmd->segname, SEG_DATA) != 0 &&
                strcmp(cur_seg_cmd->segname, SEG_DATA_CONST) != 0) continue;
            for (uint j = 0; j < cur_seg_cmd->nsects; j++) {
                struct section_64 *sect = (struct section_64 *)(cur + sizeof(struct segment_command_64)) + j;
                if ((sect->flags & SECTION_TYPE) == S_LAZY_SYMBOL_POINTERS ||
                    (sect->flags & SECTION_TYPE) == S_NON_LAZY_SYMBOL_POINTERS) {
                    perform_rebinding_with_section(rebindings, sect, slide, symtab, strtab, indirect_symtab);
                }
            }
        }
    }
}

static void _rebind_symbols_for_image(const struct mach_header *header, intptr_t slide) {
    rebind_symbols_for_image(_rebindings_head, header, slide);
}

int rebind_symbols(struct rebinding rebindings[], size_t rebindings_nel) {
    int retval = prepend_rebindings(&_rebindings_head, rebindings, rebindings_nel);
    if (retval < 0) return retval;
    if (!_rebindings_head->next) {
        _dyld_register_func_for_add_image(_rebind_symbols_for_image);
    } else {
        uint32_t c = _dyld_image_count();
        for (uint32_t i = 0; i < c; i++) {
            _rebind_symbols_for_image(_dyld_get_image_header(i), _dyld_get_image_vmaddr_slide(i));
        }
    }
    return retval;
}

// ========== 防检测辅助函数 ==========
static NSArray *blockedPaths() {
    static NSArray *paths = nil;
    if (!paths) {
        paths = @[
            @"/Applications/Cydia.app",
            @"/usr/sbin/sshd",
            @"/bin/bash",
            @"/etc/apt",
            @"/Library/MobileSubstrate/MobileSubstrate.dylib",
            @"/var/checkra1n",
            @"/usr/bin/ssh",
            @"/var/lib/cydia"
        ];
    }
    return paths;
}

static BOOL isPathBlocked(const char *path) {
    if (!path) return NO;
    NSString *pathStr = [NSString stringWithUTF8String:path];
    for (NSString *blocked in blockedPaths()) {
        if ([pathStr hasPrefix:blocked] || [pathStr isEqualToString:blocked]) {
            return YES;
        }
    }
    if (strstr(path, "MobileSubstrate") || strstr(path, "Substitute") ||
        strstr(path, "cycript") || strstr(path, "frida")) {
        return YES;
    }
    return NO;
}

// ========== 原始函数指针 ==========
static int (*orig_access)(const char *, int);
static int (*orig_stat)(const char *, struct stat *);
static int (*orig_lstat)(const char *, struct stat *);
static int (*orig_open)(const char *, int, ...);
static int (*orig_sysctl)(int *, u_int, void *, size_t *, void *, size_t);
static char *(*orig_getenv)(const char *);
static const char *(*orig_dyld_get_image_name)(uint32_t image_index);

// ========== 替换函数 ==========
static int my_access(const char *path, int mode) {
    if (isPathBlocked(path)) { errno = ENOENT; return -1; }
    return orig_access(path, mode);
}

static int my_stat(const char *path, struct stat *buf) {
    if (isPathBlocked(path)) { errno = ENOENT; return -1; }
    return orig_stat(path, buf);
}

static int my_lstat(const char *path, struct stat *buf) {
    if (isPathBlocked(path)) { errno = ENOENT; return -1; }
    return orig_lstat(path, buf);
}

static int my_open(const char *path, int flags, ...) {
    if (isPathBlocked(path)) { errno = ENOENT; return -1; }
    va_list args;
    va_start(args, flags);
    mode_t mode = va_arg(args, int);
    va_end(args);
    return orig_open(path, flags, mode);
}

static int my_sysctl(int *name, u_int namelen, void *oldp, size_t *oldlenp, void *newp, size_t newlen) {
    if (name[0] == CTL_KERN && name[1] == KERN_PROC && name[2] == KERN_PROC_PID) {
        int ret = orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
        if (ret == 0 && oldp) {
            struct kinfo_proc *info = (struct kinfo_proc *)oldp;
            info->kp_proc.p_flag &= ~P_TRACED;
        }
        return ret;
    }
    if (name[0] == CTL_KERN && (name[1] == KERN_PROC || name[1] == KERN_PROC2)) {
        errno = EPERM;
        return -1;
    }
    return orig_sysctl(name, namelen, oldp, oldlenp, newp, newlen);
}

static char *my_getenv(const char *name) {
    if (strcmp(name, "DYLD_INSERT_LIBRARIES") == 0 ||
        strcmp(name, "DYLD_FORCE_FLAT_NAMESPACE") == 0) {
        return NULL;
    }
    return orig_getenv(name);
}

static const char *my_dyld_get_image_name(uint32_t image_index) {
    const char *name = orig_dyld_get_image_name(image_index);
    if (name && (strstr(name, "MobileSubstrate") || strstr(name, "Substitute") ||
                 strstr(name, "frida") || strstr(name, "cycript"))) {
        return NULL;
    }
    return name;
}

// ========== NSFileManager Hook ==========
static BOOL (*orig_fileExistsAtPath)(id, SEL, NSString *);
static BOOL replaced_fileExistsAtPath(id self, SEL _cmd, NSString *path) {
    if (isPathBlocked([path UTF8String])) return NO;
    return orig_fileExistsAtPath(self, _cmd, path);
}

// ========== 安装入口 ==========
@implementation AntiDetection

+ (void)install {
    struct rebinding rebindings[] = {
        {"access", my_access, (void **)&orig_access},
        {"stat", my_stat, (void **)&orig_stat},
        {"lstat", my_lstat, (void **)&orig_lstat},
        {"open", my_open, (void **)&orig_open},
        {"sysctl", my_sysctl, (void **)&orig_sysctl},
        {"getenv", my_getenv, (void **)&orig_getenv},
        {"_dyld_get_image_name", my_dyld_get_image_name, (void **)&orig_dyld_get_image_name}
    };
    rebind_symbols(rebindings, sizeof(rebindings) / sizeof(rebindings[0]));

    Class cls = [NSFileManager class];
    SEL sel = @selector(fileExistsAtPath:);
    Method m = class_getInstanceMethod(cls, sel);
    if (m) {
        orig_fileExistsAtPath = (BOOL (*)(id, SEL, NSString *))method_getImplementation(m);
        method_setImplementation(m, (IMP)replaced_fileExistsAtPath);
    }
}

@end
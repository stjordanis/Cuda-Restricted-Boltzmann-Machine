#include "rbm.h"
#include "colors.h"
#include "throw_error.h"
#include <iostream>
#include <iomanip>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
int change_dir(const char* dir_name){
    struct stat st = {0};
    /* Create directory if not exists */
    if (stat(dir_name, &st) == -1) {
        if(mkdir(dir_name, 0777) == -1){
            // std::cerr << COLOR_BOLD << COLOR_RED_BLACK << "Fail creating directory: " << dir_name << COLOR_NORMAL << std::endl;
            throw_error_with_reason("Fail creating directory: " << dir_name);
            exit(1);
        }
    }
    if(chdir(dir_name) == -1){
        throw_error_with_reason("Fail changing directory to: " << dir_name);
        exit(1);
    }
}
int main(int argc, char *argv[])
{
    if(argc != 6){
        std::cerr << "Usage: " << argv[0] << " [Output directory] [Training data] [Learning rate] [Epoch number] [Train data size]\n";
        exit(1);
    }
    const char* out_dir         = argv[1];
    const char* train_data_file = argv[2];
    const float learning_rate   = atof(argv[3]);
    const int   n_epoch         = atoi(argv[4]);
    const int   train_size      = atoi(argv[5]);

    std::cout << COLOR_BOLD << "Starting RBM with the following configurations:" << COLOR_NORMAL << std::endl;
    std::cout << COLOR_GREEN_BLACK;
    std::cout << std::setw(20) << "[Output directory]" << " = " << out_dir         << std::endl;
    std::cout << std::setw(20) << "[Training data]"    << " = " << train_data_file << std::endl;
    std::cout << std::setw(20) << "[Learning rate]"    << " = " << learning_rate   << std::endl;
    std::cout << std::setw(20) << "[Epoch number]"     << " = " << n_epoch         << std::endl;
    std::cout << std::setw(20) << "[Train data size]"  << " = " << train_size      << std::endl;
    std::cout << COLOR_NORMAL;

    MnistReader reader(train_data_file, train_size);
    change_dir(out_dir);

    RBM rbm(784, 500, learning_rate, n_epoch, reader);
    rbm.train();
    return 0;
}
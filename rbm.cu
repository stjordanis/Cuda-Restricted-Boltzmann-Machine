#include "rbm.h"
#include "debug.h"
#include "messages.h"

/*
 *   ==========================
 *   Helper function prototypes
 *   ==========================
 */
template <bool do_sample>
__global__ void add_sigmoid(float* x, const float* y, int size, curandState* rngs);
__global__ void add_diff(float* a, const float* x, const float* y, const float c, int size);
__global__ void vec_sample(float* v, int size, curandState* rngs);
__forceinline__ __device__ float sample( float v, curandState* globalState );
__forceinline__ __device__ float sigmoidf(float in);
/*
 * Helper struct used to compute square error
 */
struct Square_diff{
    __host__ __device__ float operator()(const float &lhs, const float &rhs) const {
        return (lhs - rhs)*(lhs - rhs);
    }
};
/*   ===========================   */

RBM::RBM(int _n_visible, int _n_hidden, float _learning_rate, int _n_epoch, MnistReader& _reader):
    n_visible(_n_visible), n_hidden(_n_hidden), learning_rate(_learning_rate), n_epoch(_n_epoch),
    reader(_reader){

    cudaErrCheck(cudaMalloc((void**)&(this->pW), _n_visible*_n_hidden*sizeof(float)));
    cudaErrCheck(cudaMalloc((void**)&(this->pb), _n_visible*sizeof(float)));
    cudaErrCheck(cudaMalloc((void**)&(this->pc), _n_hidden*sizeof(float)));

    // Initialize weights
    random_fill_range<<<CeilDiv(_n_visible*_n_hidden,256),256>>>(this->pW, _n_visible*_n_hidden, -0.15, 0.15);
    random_fill_range<<<CeilDiv(n_visible,128),128>>>(this->pb, _n_visible, .0, .1);
    random_fill_range<<<CeilDiv(n_hidden,128),128>>>(this->pc, _n_hidden, .0, .1);
    
#ifdef DEBUG
    /*
    print_gpu("pW", this->pW, _n_visible*_n_hidden); 
    print_gpu("pb", this->pb, _n_visible); 
    print_gpu("pc", this->pc, _n_hidden); 
    */
#endif

    this->n_train_data = reader.get_total();
}
RBM::~RBM(){

    cudaErrCheck(cudaFree(pW));
    cudaErrCheck(cudaFree(pb));
    cudaErrCheck(cudaFree(pc));

    // Free the memory allocated in these functions
    calculate_cost_each(NULL);
    do_contrastive_divergence(NULL);
}
void RBM::update_w(const float* h_0, const float* v_0, const float* h_k, const float* v_k){
    // W += learning_rate * (outer(h_0, v_0) - outer(h_k, v_k))
    add_outer_prod(this->pW, h_0, v_0, n_hidden, n_visible,  learning_rate);
    add_outer_prod(this->pW, h_k, v_k, n_hidden, n_visible, -learning_rate);
}
void RBM::update_b(const float* v_0, const float* v_k){
    // b += learning_rate * (v_0 - v_k)
    const int bsize = 128;
    const int gsize = CeilDiv(n_visible,bsize);
    add_diff<<<gsize,bsize>>>(this->pb, v_0, v_k, learning_rate, n_visible);
    KERNEL_CHECK;
}
void RBM::update_c(const float* h_0, const float* h_k){
    // c += learning_rate * (h_0 - h_k)
    const int bsize = 128;
    const int gsize = CeilDiv(n_hidden,bsize);
    add_diff<<<gsize,bsize>>>(this->pc, h_0, h_k, learning_rate, n_hidden);
    KERNEL_CHECK;
}
void RBM::do_contrastive_divergence(const float* v_0){
    static float *v_k = NULL, *h_k = NULL, *h_0 = NULL;
    if(v_k == NULL){
        cudaErrCheck(cudaMalloc((void**) &v_k, sizeof(float)*n_visible));
        cudaErrCheck(cudaMalloc((void**) &h_k, sizeof(float)*n_hidden));
        cudaErrCheck(cudaMalloc((void**) &h_0, sizeof(float)*n_hidden));
    }
    if(v_0 == NULL && v_k){
        cudaFree(v_k);
        cudaFree(h_k);
        cudaFree(h_0);
        return;
    }
    
    /*
    // CD-k
    // Initial hidden unit sampling: h0
    get_h_given_v<true>( h_0, v_0 );
    get_v_given_h<true>( h_k, v_k );

    cudaMemcpy(v_k, v_0, sizeof(float)*n_visible, cudaMemcpyDeviceToDevice);

    // Gibbs sampling
    for(int i = 0; i < this->n_cd_iter; ++i){
        get_h_given_v<true>( h_k, v_k );
        get_v_given_h<true>( h_k, v_k );
    }

    get_h_given_v<false>( h_k, v_k );
    */

    // CD-1
    /* see machinelearning.org/archive/icml2008/papers/601.pdf */ 
    float* h_s = h_k;

    /* positive phase */
    get_h_given_v<false>( h_0, v_0 );        /* h_0  <- sigmoid(W*v_0 + c) */

    /* negative phase: CD-1 */
    sample_h(h_s, h_0);                      /* h_s  ~ sigmoid(W*v_0 + c) */
    get_v_given_h<true>( h_s, v_k );         /* v_k  ~ sigmoid(W*h_s + b) */
    get_h_given_v<false>( h_k, v_k );        /* h_k <- sigmoid(W*v_k + c) */

    this->update_w( h_0, v_0, h_k, v_k );
    this->update_b( v_0, v_k );
    this->update_c( h_0, h_k );
}

void RBM::train(){
    for(int i = 0; i < this->n_epoch; ++i){
        train_step();
        /* calculate cost here */
        float cost = calculate_cost();
        std::cout.precision(3);
        print_train_error(i+1, cost);
    }
}
void RBM::train_step(){
    for(int i = 0; i < this->n_train_data; ++i){
        const float* cur_data = reader.get_example_at(i);
        /* print_gpu("cur_data", cur_data, n_visible, float);  */
        do_contrastive_divergence(cur_data);
    }
}
float RBM::calculate_cost(){
    const int random_sample = 5;
    float mean_cost = 0.0;
    std::srand(std::time(0));
    for(int i = 0; i < random_sample; ++i){
        int rand_i = std::rand() % n_train_data;
        const float* rand_data = reader.get_example_at(rand_i);
        mean_cost += calculate_cost_each(rand_data);
    }
    return mean_cost / (float)random_sample;
}
float RBM::calculate_cost_each(const float* v_0){
    static float *h_s = NULL, *v_r = NULL;
    if(h_s == NULL){
        cudaErrCheck(cudaMalloc((void**)&v_r, sizeof(float)*n_visible));
        cudaErrCheck(cudaMalloc((void**)&h_s, sizeof(float)*n_hidden));
    }
    if(v_0 == NULL && thrust::raw_pointer_cast(v_r) != NULL){
        cudaErrCheck(cudaFree(v_r));
        cudaErrCheck(cudaFree(h_s));
        return 0.0;
    }
    
    get_h_given_v<true>( h_s, v_0 );  /* h_s  ~ sigmoid(W*v_0 + c) */
    /* reconstruction */
    get_v_given_h<false>( h_s, v_r ); /* v_r  <- sigmoid(W*h_s + b) */
    
    thrust::device_ptr<float> dv_r(v_r);
    thrust::device_ptr<float> dh_s(h_s);
    thrust::device_ptr<const float> dv_0(v_0);
    /* print_gpu("v_r", v_r, n_visible, float);  */
    try {
        // cost = sqrt(sum((v_r - v_0)^2)/n)
        thrust::transform(thrust::device, dv_r, dv_r + n_visible, dv_0, dv_r, Square_diff());
        float sum = thrust::reduce(thrust::device, dv_r, dv_r + n_visible);
        return sqrt(sum/n_visible);
    }
    catch(thrust::system_error &e){
        throw_error("Thrust error: + " << e.what());
        return 0.0;
    }
}
__global__ void add_diff(float* a, const float* x, const float* y, const float c, int size){
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if( i < size )
        a[i] += c*(x[i] - y[i]);
}
/*
 * make a sample out of h_0 (the pdf of hidden state), and store the result to h_s
 */
void RBM::sample_h(float* h_s, const float* h_0){
    cudaErrCheck(cudaMemcpy(h_s, h_0, sizeof(float)*n_hidden, cudaMemcpyDeviceToDevice));
    const int bsize = 128;
    const int gsize = CeilDiv(n_hidden,bsize);
    vec_sample<<<gsize,bsize>>>(h_s, n_hidden, this->rngs);
    KERNEL_CHECK;
}

template <bool do_sample>
float* RBM::get_h_given_v(float* h, const float* v){
    // h = sigmoid(dot(v, W) + c)
    matrix_mul(v, this->pW, h, 1, n_visible, n_visible, n_hidden, n_hidden);
    const int bsize = 128;
    const int gsize = CeilDiv(n_hidden,bsize);
    add_sigmoid<do_sample><<<gsize,bsize>>>(h, this->pc, n_hidden, this->rngs);
    KERNEL_CHECK;
    return h;
}

template <bool do_sample>
float* RBM::get_v_given_h(const float* h, float* v){
    // v = sigmoid(dot(h, W) + b)
    /* Transpose the second matrix */
    matrix_mul_tranpose_first(h, this->pW, v, 1, n_hidden, n_visible, n_hidden, n_visible); 
    const int bsize = 128;
    const int gsize = CeilDiv(n_visible,bsize);
    add_sigmoid<do_sample><<<gsize,bsize>>>(v, this->pb, n_visible, this->rngs);
    KERNEL_CHECK;
    return v;
}

/*
 * =-=-=-=-=-=-=-=-=-=-=-=-=-=
 *   Helper functions below
 * =-=-=-=-=-=-=-=-=-=-=-=-=-=
 */

/*
 * x = sigmoid(x + y)
 */
template <bool do_sample>
__global__ void add_sigmoid(float* x, const float* y, int size){
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if( i < size ){
        float v = sigmoidf(x[i] + y[i]);
        x[i] = do_sample ? get_sample(v) : v;
    }
}

/*
 * Fill array with random value in [low,high]
 */
__global__ void random_fill_range(float* v, int size, float low, float high){
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if( i < size ){
        float range = high - low;
        v[i] = get_rand()*range + low;
    }
}

/*
 * Apply Bernoulli sampling on vector v
 */
__global__ void vec_sample(float* v, int size){
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    if( i < size ){
        v[i] = get_sample(v[i]);
    }
}

/*
 * Do a Bernoulli sample
 */
__forceinline__ __device__ float get_sample(float f) {
    return get_rand() > f ? 0.0 : 1.0;
}
/*
 * Get a random number in [0,1]
 */
__forceinline__ __device__ float get_rand() {
    curandState state;
    curand_init((unsigned long long)clock() + threadIdx.x, 0, 0, &state);
    return curand_uniform(&state);
}

/*
 * Compute the Sigmoid function
 */
__forceinline__ __device__ float sigmoidf(float in) {
    // raw approximation to sigmoid function
    return in / (1.f + fabsf(in));  
}

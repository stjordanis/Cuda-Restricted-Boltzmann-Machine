#include "rbm.h"

dim3 gdim(CeilDiv(wt,32), CeilDiv(ht,16)), bdim(32,16);

RBM::RBM(int _n_visible, int _n_hidden, float _learning_rate, int _n_cd_iter, int _n_epoch){
    W = thrust::device_malloc<float>(_n_visible * _n_hidden);
    b = thrust::device_malloc<float>(_n_visible);
    c = thrust::device_malloc<float>(_n_hidden);
    pW = thrust::raw_pointer_cast(W);
    pb = thrust::raw_pointer_cast(b);
    pc = thrust::raw_pointer_cast(c);
    randn(pW, _n_visible * _n_hidden);
    randn(pb, _n_visible);
    randn(pc, _n_hidden);
}
void RBM::update_w(float* h_0, float* v_0, float* h_k, float* v_k){
    // W += learning_rate * (outer(h_0, v_0) - outer(h_k, v_k))
    add_outer_prod(this->W, h_0, v_0, n_hidden, n_visible,  learning_rate);
    add_outer_prod(this->W, h_k, v_k, n_hidden, n_visible, -learning_rate);
}
void RBM::update_b(float* v_0, float* v_k){
    // b += learning_rate * (v_0 - v_k)
    const int bsize = 128;
    const int gsize = CeilDiv(n_visible,bsize);
    add_diff<<<gsize,bsize>>>(this->b, v_0, v_k, learning_rate, n_visible);
}
void RBM::update_c(float* h_0, float* h_k){
    // c += learning_rate * (h_0 - h_k)
    const int bsize = 128;
    const int gsize = CeilDiv(n_hidden,bsize);
    add_diff<<<gsize,bsize>>>(this->c, h_0, h_k, learning_rate, n_hidden);
}
void RBM::do_contrastive_divergence(const float* v_0){
    static float *v_k = NULL, *h_k = NULL, *h_0 = NULL;
    if(v_k == NULL){
        cudaMalloc((void**) &v_k, sizeof(float)*n_visible);
        cudaMalloc((void**) &h_k, sizeof(float)*n_hidden);
        cudaMalloc((void**) &h_0, sizeof(float)*n_hidden);
    }

    /* Initial hidden unit sampling: h0 */
    this->get_h_given_v(h_0, v_0);

    cudaMemcpy(v_k, v_0, sizeof(float)*n_visible, cudaMemcpyDeviceToDevice);

    // Gibbs sampling
    for(int i = 0; i < this->n_cd_iter; ++i){
        this->get_h_given_v( h_k, v_k );
        this->get_v_given_h( h_k, v_k );
    }

    this->get_h_given_v( h_k, v_k );

    this->update_w( h_0, v_0, h_k, v_k );
    this->update_b( v_0, v_k );
    this->update_c( h_0, h_k );
}
void RBM::get_h_given_v(float* h, const float* v){
    // h = sigmoid(dot(v, W) + c)
    matrixMul(v, this->W, h, 1, n_visible, n_hidden)
    thrust::transform(h, h + n_hidden, this->c, h, thrust::plus<int>()); 
    thrust::transform(h, h + n_hidden, sigmoid()); 
}
void RBM::get_v_given_h(const float* h, const float* v){
    // h = sigmoid(dot(v, W) + c)
    /* Transpose the second matrix */
    matrixMulTranspose(h, this->W, v, 1, n_visible, n_hidden, 2); 
    thrust::transform(h, h + n_hidden, this->c, h, thrust::plus<int>()); 
    thrust::transform(h, h + n_hidden, sigmoid()); 
}
void RBM::train(std::vector<float*> training_data, int minibatch_index){
    for(int i = minibatch_index; i < minibatch_index + minibatch_size; ++i){
        do_contrastive_divergence(train_data[i]);
        /* calculate cost here */
    }
}
void RBM::init_train_data(std::vector<float*> train_data){
    unsigned seed = std::chrono::system_clock::now().time_since_epoch().count();
    shuffle (train_data.begin(), train_data.end(), std::default_random_engine(seed));
}

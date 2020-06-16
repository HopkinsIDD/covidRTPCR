//
// This Stan program defines a model for adjusting a predicted
// seroincidence by the sensitivity and specificity of the diagnostic.
// We assume that the sensitivity of the diagnostic decays with time.
//
// Learn more about model development with Stan at:
//
//    http://mc-stan.org/users/interfaces/rstan.html
//    https://github.com/stan-dev/rstan/wiki/RStan-Getting-Started
//

// We have RT-PCR data from two studies where patients eventually developed
// antibodies (IgG or IgM) to covid-19.
// 'N' is the number of rows in our input data, which has a row for each number of
// days since symptom onset. 'T_max' is the number of days that we would like to
// predict into the future. 'test_n' is the number of people who were tested
// and 'test_pos' is the number of people who tested positive. 't_symp_test' is
// the number of days since symptom onset. 'exposed_n' and 'exposed_pos' are
// numbers to estimate the attack rate of covid-19 from other papers.
data {
    int<lower=1> N;
    int<lower=1> J; // number of studies
    int<lower=1> T_max;
    int<lower=1> test_n[N];
    int<lower=0> test_pos[N];
    real<lower=0> t_symp_test[N];
    int<lower=1> study_idx[N];
    int<lower=1> exposed_n;
    int<lower=0> exposed_pos;
    real spec;
}

// 't_new' is the log-time since exposure for the predicted times since exposure.
transformed data {
    vector[T_max] t_new;
    int test_sum;

    for(i in 1:T_max){
        t_new[i] = log(i);
    }
    test_sum = sum(test_n);
}

// the beta terms are the coefficients for the cubic polynomial for log-time.
// 'attack_rate' is the probability of infection given exposure.
parameters {
    real beta_0;
    real beta_1;
    real beta_2;
    real beta_3;
    real<lower=0> sigma;
    vector[J] eta;
    real<lower=0, upper=1> attack_rate;
    vector<lower=0>[test_sum] inc_periods;
    real<lower=0> logmean;
    real<lower=0> logsd;
}

transformed parameters{
    vector[N] t;
    real t_mean;
    real<lower=0> t_sd;
    vector[N] t_ort;
    vector[N] t_ort2;
    vector[N] t_ort3;
    vector[J] beta_j;
    vector[N] mu;
    real<lower=0> t_exp_symp;

    t_exp_symp = mean(inc_periods); // find the average incubation period

    for(i in 1:N){
        t[i] = log(t_symp_test[i] + t_exp_symp); // time from infection to test
    }

    // standardize time since infection
    t_mean=mean(t);
    t_sd=sd(t);

    for(i in 1:N){
        t_ort[i] = (t[i]-t_mean)/t_sd;
        t_ort2[i] = t_ort[i]^2;
        t_ort3[i] = t_ort[i]^3;
    }

    beta_j = beta_0 + sigma*eta;
    for(i in 1:N){
        mu[i] = beta_j[study_idx[i]]+beta_1*t_ort[i]+beta_2*t_ort[i]^2+beta_3*t_ort[i]^3;
    }
}

model {
    target += binomial_lpmf(exposed_pos | exposed_n, attack_rate);
    target += binomial_logit_lpmf(test_pos | test_n, mu);
    target += normal_lpdf(eta | 0, 1);
    target += lognormal_lpdf(inc_periods | logmean, logsd);
    target += normal_lpdf(logmean | 1.621, 0.063); // mean and standard deviation of logmean from Lauer et al.
    target += normal_lpdf(logsd | 0.418, 0.068); // mean and standard deviation of logsd from Lauer et al.
}

// 'sens' is the sensitivity of the RT-PCR over time for the predicted values.
// 'npv' is estimated using 'sens' and 'attack_rate'. We can also find the
// log-likelihood of the model for estimating the observed values, with the caveat
// that we don't know the likelihood of the estimates occurring prior to symptom
// onset.
generated quantities{
    vector<lower=0, upper=1>[T_max] sens;
    vector<lower=0, upper=1>[T_max] npv;
    vector[T_max] t_new_ort;
    vector[T_max] t_new_ort2;
    vector[T_max] t_new_ort3;
    vector[N] log_lik;

    t_new_ort = (t_new-t_mean)/t_sd;
    for(i in 1:T_max){
        t_new_ort2[i] = t_new_ort[i]^2;
        t_new_ort3[i] = t_new_ort[i]^3;
    }

    sens=inv_logit(beta_0+beta_1*t_new_ort+beta_2*t_new_ort2+beta_3*t_new_ort3);
    for(i in 1:T_max){
        npv[i]=(1-attack_rate)/((1-sens[i])*attack_rate+(1-attack_rate));
    }

    for(i in 1:N){
        log_lik[i] = binomial_logit_lpmf(test_pos[i] | test_n[i], mu[i]);
    }
}
